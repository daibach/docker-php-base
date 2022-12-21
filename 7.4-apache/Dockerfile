FROM php:7.4-apache

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends git zlib1g-dev ca-certificates libpng-dev libzip-dev libicu-dev zip unzip
RUN docker-php-ext-install pdo pdo_mysql mysqli intl

# Harden PHP
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
RUN sed -i -e s/expose_php=on/expose_php=off/g "$PHP_INI_DIR/php.ini"

# Harden Apache and enable modules
RUN { \
		echo ServerTokens Prod; \
		echo ServerSignature Off; \
    echo TraceEnable Off; \
		echo Header always unset X-Powered-By; \
    echo Header unset X-Powered-By; \
  } | tee "$APACHE_CONFDIR/conf-available/docker-harden.conf" \
  && a2enmod headers \
  && a2enmod rewrite \
  && a2disconf security \
	&& a2enconf docker-harden \
  && service apache2 restart


