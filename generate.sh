#!/bin/sh
set -xe

gen() {
  BASE=$1
  NAME=$2
  BASE_TYPE=$3
  INCLUDE_CRON=$4

  mkdir -p ${NAME}
  echo "FROM php:${BASE}-${BASE_TYPE}" > ${NAME}/Dockerfile
  echo '' >> ${NAME}/Dockerfile

  echo '# Install dependencies' >> ${NAME}/Dockerfile
  echo 'RUN apt-get update && apt-get install -y --no-install-recommends git zlib1g-dev ca-certificates libpng-dev libzip-dev' >> ${NAME}/Dockerfile
  echo 'RUN docker-php-ext-install pdo pdo_mysql mysqli' >> ${NAME}/Dockerfile

  echo '' >> ${NAME}/Dockerfile

  echo '# Harden PHP' >> ${NAME}/Dockerfile
  echo 'RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"' >> ${NAME}/Dockerfile
  echo 'RUN sed -i -e 's/expose_php=on/expose_php=off/g' "$PHP_INI_DIR/php.ini"' >> ${NAME}/Dockerfile
  echo '' >> ${NAME}/Dockerfile

  if [ ${BASE_TYPE} == 'apache' ]; then
    echo '# Harden Apache and enable modules' >> ${NAME}/Dockerfile
    echo 'RUN { \' >> ${NAME}/Dockerfile
    echo '		echo 'ServerTokens Prod'; \' >> ${NAME}/Dockerfile
    echo '		echo 'ServerSignature Off'; \' >> ${NAME}/Dockerfile
    echo '    echo 'TraceEnable Off'; \' >> ${NAME}/Dockerfile
    echo '		echo 'Header always unset "X-Powered-By"'; \' >> ${NAME}/Dockerfile
    echo '    echo 'Header unset "X-Powered-By"'; \' >> ${NAME}/Dockerfile
    echo '  } | tee "$APACHE_CONFDIR/conf-available/docker-harden.conf" \' >> ${NAME}/Dockerfile
    echo '  && a2enmod headers \' >> ${NAME}/Dockerfile
    echo '  && a2enmod rewrite \' >> ${NAME}/Dockerfile
    echo '  && a2disconf security \' >> ${NAME}/Dockerfile
    echo '	&& a2enconf docker-harden \' >> ${NAME}/Dockerfile
    echo '  && service apache2 restart \' >> ${NAME}/Dockerfile
    echo '' >> ${NAME}/Dockerfile
  fi

  if [ ${INCLUDE_CRON} == 'cron' ]; then
    echo '# Install cron' >> ${NAME}/Dockerfile >> ${NAME}/Dockerfile
    echo 'RUN apt-get -y install cron' >> ${NAME}/Dockerfile
    echo 'RUN touch /var/log/cron.log' >> ${NAME}/Dockerfile
    echo '' >> ${NAME}/Dockerfile
  fi

  echo '' >> ${NAME}/Dockerfile
}

gen 7.4 7.4-apache apache nocron
gen 7.4 7.4-apache-cron apache cron
gen 7.4 7.4-cli cli nocron
gen 8.0 8.0-apache apache nocron
gen 8.0 8.0-apache-cron apache cron
gen 8.0 8.0-cli cli nocron
