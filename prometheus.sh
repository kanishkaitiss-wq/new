#!/bin/bash

# ============================================================
# Prometheus Installation Script
# Operating System: Debian 13
#
# Installs:
#   1. Prometheus server
#   2. Prometheus Node Exporter
#   3. systemd services
#   4. Prometheus configuration
#
# Prometheus UI:      http://SERVER_IP:9090
# Node Exporter:      http://SERVER_IP:9100/metrics
# ============================================================

# Exit if a command fails, an unset variable is used,
# or a command in a pipeline fails.
set -Eeuo pipefail

# ------------------------------------------------------------
# 1. Check that the script is running as root.
# ------------------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script using sudo."
    echo "Example: sudo bash install_prometheus.sh"
    exit 1
fi

# ------------------------------------------------------------
# 2. Verify the operating system.
# ------------------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot identify the operating system."
    exit 1
fi

# Load operating system information.
source /etc/os-release

if [[ "${ID}" != "debian" ]]; then
    echo "ERROR: This script is intended for Debian."
    exit 1
fi

echo "=========================================="
echo " Starting Prometheus installation"
echo " Debian version: ${VERSION_ID:-unknown}"
echo "=========================================="

# ------------------------------------------------------------
# 3. Update APT and install required packages.
#
# prometheus:
#   Collects, stores, and queries monitoring metrics.
#
# prometheus-node-exporter:
#   Exposes CPU, memory, disk, and network metrics.
# ------------------------------------------------------------

echo "[1/7] Installing Prometheus and Node Exporter..."

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    prometheus \
    prometheus-node-exporter \
    curl \
    ca-certificates

# ------------------------------------------------------------
# 4. Back up the existing configuration, if present.
#
# This helps preserve the previous configuration before
# the script writes its own basic monitoring configuration.
# ------------------------------------------------------------

if [[ -f /etc/prometheus/prometheus.yml ]]; then
    BACKUP_FILE="/etc/prometheus/prometheus.yml.backup.$(date +%Y%m%d%H%M%S)"
    cp -a /etc/prometheus/prometheus.yml "${BACKUP_FILE}"
    echo "Previous configuration backed up to ${BACKUP_FILE}"
fi

# ------------------------------------------------------------
# 5. Create the Prometheus configuration.
#
# Prometheus collects metrics from:
#   localhost:9090 = Prometheus itself
#   localhost:9100 = Node Exporter
#
# Metrics are collected every 15 seconds.
# ------------------------------------------------------------

echo "[2/7] Writing Prometheus configuration..."

cat > /etc/prometheus/prometheus.yml <<'YAML'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Monitor Prometheus itself.
  - job_name: "prometheus"
    static_configs:
      - targets: ["127.0.0.1:9090"]

  # Monitor the Debian virtual machine.
  - job_name: "debian-node"
    static_configs:
      - targets: ["127.0.0.1:9100"]
YAML

# ------------------------------------------------------------
# 6. Configure the Prometheus web interface.
#
# Listen on all VM network interfaces so the UI can be
# reached from the host or another machine on the network.
#
# IMPORTANT:
# Restrict access using your firewall or private network.
# Do not expose port 9090 directly to the public internet.
# ------------------------------------------------------------

echo "[3/7] Configuring the Prometheus listen address..."

DEFAULT_FILE="/etc/default/prometheus"

# Preserve the existing defaults file before editing it.
if [[ -f "${DEFAULT_FILE}" ]]; then
    cp -a "${DEFAULT_FILE}" \
        "${DEFAULT_FILE}.backup.$(date +%Y%m%d%H%M%S)"
fi

# Remove any existing ARGS assignment so it cannot override
# the listen address specified below.
if [[ -f "${DEFAULT_FILE}" ]]; then
    sed -i '/^[[:space:]]*ARGS=/d' "${DEFAULT_FILE}"
fi

# Debian's Prometheus systemd service reads this setting.
cat >> "${DEFAULT_FILE}" <<'EOF'

# Allow access to the web UI through the VM network.
ARGS="--web.listen-address=0.0.0.0:9090"
EOF

# ------------------------------------------------------------
# 7. Validate configuration and enable services.
# ------------------------------------------------------------

echo "[4/7] Validating Prometheus configuration..."

promtool check config /etc/prometheus/prometheus.yml

echo "[5/7] Enabling Prometheus service..."

systemctl enable prometheus
systemctl restart prometheus

echo "[6/7] Enabling Node Exporter service..."

systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

# ------------------------------------------------------------
# 8. Wait briefly and check service status.
# ------------------------------------------------------------

echo "[7/7] Checking services..."

sleep 3

if ! systemctl is-active --quiet prometheus; then
    echo "ERROR: Prometheus failed to start."
    journalctl -u prometheus -n 50 --no-pager
    exit 1
fi

if ! systemctl is-active --quiet prometheus-node-exporter; then
    echo "ERROR: Node Exporter failed to start."
    journalctl -u prometheus-node-exporter -n 50 --no-pager
    exit 1
fi

# ------------------------------------------------------------
# 9. Print installation results.
# ------------------------------------------------------------

echo
echo "=========================================="
echo " Installation completed successfully!"
echo "=========================================="

echo
echo "Prometheus service:"
systemctl --no-pager --full status prometheus | head -n 8

echo
echo "Node Exporter service:"
systemctl --no-pager --full status prometheus-node-exporter | head -n 8

echo
echo "Listening ports:"
ss -lnt | grep -E ':(9090|9100)[[:space:]]' || true

echo
echo "Prometheus local health check:"
if curl -fsS http://127.0.0.1:9090/-/healthy; then
    echo
    echo "Prometheus health check passed."
else
    echo "WARNING: Prometheus health check failed."
fi

IP=$(hostname -I | awk '{print $1}')

echo
echo "Open the Prometheus UI at:"
echo "http://$IP:9090"

echo
echo "Node Exporter metrics endpoint:"
echo "http://$IP:9100/metrics"


echo
echo "ZINGALALA - INSTALLED SUCCESSFULLY"
