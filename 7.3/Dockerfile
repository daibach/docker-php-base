FROM php:7.3-apache

# Install dependencies and extensions
RUN apt-get update && apt-get install -y --no-install-recommends git zlib1g-dev ca-certificates libpng-dev libzip-dev
RUN docker-php-ext-install pdo pdo_mysql mysqli
RUN docker-php-ext-install mbstring
RUN a2enmod rewrite

# Harden php and apache
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
RUN { \
		echo ServerTokens Prod; \
		echo ServerSignature Off; \
    echo TraceEnable Off; \
		echo Header always unset X-Powered-By; \
    echo Header unset X-Powered-By; \
  } | tee "$APACHE_CONFDIR/conf-available/docker-harden.conf" \
  && a2enmod headers \
  && a2disconf security \
	&& a2enconf docker-harden \
  && service apache2 restart
RUN sed -i -e s/expose_php=on/expose_php=off/g "$PHP_INI_DIR/php.ini"

