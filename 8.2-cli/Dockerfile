FROM php:8.2-cli

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \ 
   git \
   zlib1g-dev \
   ca-certificates \
   cron \
   libpng-dev \
   libzip-dev \
   libicu-dev \
   zip \
   unzip \
   && rm -rf /var/lib/apt/lists/* \
   docker-php-ext-install pdo pdo_mysql mysqli intl

# Harden PHP
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
RUN sed -i -e s/expose_php=on/expose_php=off/g "$PHP_INI_DIR/php.ini"

# Install composer
RUN php -r "readfile('http://getcomposer.org/installer');" | php -- --install-dir=/usr/bin/ --filename=composer


