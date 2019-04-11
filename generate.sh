#!/bin/sh
set -xe

gen() {
  BASE=$1
  NAME=$2

  mkdir -p ${NAME}
  echo "FROM php:${BASE}-apache" > ${NAME}/Dockerfile
  echo '' >> ${NAME}/Dockerfile
  echo '# Install dependencies and extensions' >> ${NAME}/Dockerfile
  echo 'RUN apt-get update && apt-get install -y --no-install-recommends git zlib1g-dev ca-certificates libpng-dev libzip-dev' >> ${NAME}/Dockerfile
  echo 'RUN docker-php-ext-install pdo pdo_mysql mysqli' >> ${NAME}/Dockerfile
  echo 'RUN docker-php-ext-install mbstring' >> ${NAME}/Dockerfile
  echo 'RUN a2enmod rewrite' >> ${NAME}/Dockerfile
  echo '' >> ${NAME}/Dockerfile
  echo '# Harden php and apache' >> ${NAME}/Dockerfile
  echo 'RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"' >> ${NAME}/Dockerfile
  echo 'RUN { \' >> ${NAME}/Dockerfile
  echo '		echo 'ServerTokens Prod'; \' >> ${NAME}/Dockerfile
  echo '		echo 'ServerSignature Off'; \' >> ${NAME}/Dockerfile
  echo '    echo 'TraceEnable Off'; \' >> ${NAME}/Dockerfile
  echo '		echo 'Header always unset "X-Powered-By"'; \' >> ${NAME}/Dockerfile
  echo '    echo 'Header unset "X-Powered-By"'; \' >> ${NAME}/Dockerfile
  echo '  } | tee "$APACHE_CONFDIR/conf-available/docker-harden.conf" \' >> ${NAME}/Dockerfile
  echo '  && a2enmod headers \' >> ${NAME}/Dockerfile
  echo '  && a2disconf security \' >> ${NAME}/Dockerfile
  echo '	&& a2enconf docker-harden \' >> ${NAME}/Dockerfile
  echo '  && service apache2 restart' >> ${NAME}/Dockerfile
  echo 'RUN sed -i -e 's/expose_php=on/expose_php=off/g' "$PHP_INI_DIR/php.ini"' >> ${NAME}/Dockerfile
  echo '' >> ${NAME}/Dockerfile
}

gen 7.1 7.1
gen 7.2 7.2
gen 7.3 7.3
