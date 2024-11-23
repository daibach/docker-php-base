#!/bin/sh
set -xe

gen() {
  BASE=$1
  NAME=$2
  BASE_TYPE=$3
  INCLUDE_CRON=$4
  INCLUDE_COMPOSER=$5

  mkdir -p ${NAME}
  echo "FROM php:${BASE}-${BASE_TYPE}" > ${NAME}/Dockerfile
  echo '' >> ${NAME}/Dockerfile

  echo '# Install dependencies' >> ${NAME}/Dockerfile
  echo 'RUN apt-get update && apt-get install -y --no-install-recommends \ ' >> ${NAME}/Dockerfile
  echo '   git \' >> ${NAME}/Dockerfile
  echo '   zlib1g-dev \' >> ${NAME}/Dockerfile
  echo '   ca-certificates \' >> ${NAME}/Dockerfile
  echo '   libpng-dev \' >> ${NAME}/Dockerfile
  echo '   libzip-dev \' >> ${NAME}/Dockerfile
  echo '   libicu-dev \' >> ${NAME}/Dockerfile
  echo '   zip \' >> ${NAME}/Dockerfile
  echo '   unzip \' >> ${NAME}/Dockerfile
  echo '   && rm -rf /var/lib/apt/lists/* \' >> ${NAME}/Dockerfile
  echo '   docker-php-ext-install pdo pdo_mysql mysqli intl' >> ${NAME}/Dockerfile
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
    echo '  && service apache2 restart' >> ${NAME}/Dockerfile
    echo '' >> ${NAME}/Dockerfile
  fi

  if [ ${INCLUDE_CRON} == 'cron' ]; then
    echo '# Install cron' >> ${NAME}/Dockerfile
    echo 'RUN apt-get update && apt-get -y install cron' >> ${NAME}/Dockerfile
    echo 'RUN touch /var/log/cron.log' >> ${NAME}/Dockerfile
    echo '' >> ${NAME}/Dockerfile
  fi

  if [ ${INCLUDE_COMPOSER} == 'composer' ]; then
    echo '# Install composer' >> ${NAME}/Dockerfile
    echo 'RUN php -r "readfile('\''http://getcomposer.org/installer'\'');" | php -- --install-dir=/usr/bin/ --filename=composer' >> ${NAME}/Dockerfile
    echo '' >> ${NAME}/Dockerfile
  fi

  echo '' >> ${NAME}/Dockerfile
}

gen 8.0 8.0-apache apache nocron composer
gen 8.0 8.0-apache-cron apache cron composer
gen 8.0 8.0-cli cli nocron composer
gen 8.1 8.1-apache apache nocron composer
gen 8.1 8.1-apache-cron apache cron composer
gen 8.1 8.1-cli cli nocron composer
gen 8.2 8.2-apache apache nocron composer
gen 8.2 8.2-apache-cron apache cron composer
gen 8.2 8.2-cli cli nocron composer
gen 8.3 8.3-apache apache nocron composer
gen 8.3 8.3-apache-cron apache cron composer
gen 8.3 8.3-cli cli nocron composer
