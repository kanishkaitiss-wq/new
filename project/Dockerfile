FROM ubuntu:latest

RUN apt-get update && apt-get install -y apache2

COPY index.html /var/www/html/index.html

EXPOSE 80

CMD ["apachectl", "-D", "FOREGROUND"]
