FROM php:8.0-apache

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends git zlib1g-dev ca-certificates libpng-dev libzip-dev
RUN docker-php-ext-install pdo pdo_mysql mysqli

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

# Install cron
RUN apt-get update && apt-get -y install cron
RUN touch /var/log/cron.log

# Install composer
RUN php -r "readfile('http://getcomposer.org/installer');" | php -- --install-dir=/usr/bin/ --filename=composer


