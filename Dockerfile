# syntax=docker/dockerfile:1
# cedyrn/php-parent:<version>
# PHP-FPM behind Apache, with cron via supercronic. The command selects the
# roles to run (web, cron, or both); any other command is run directly.
ARG PHP_VERSION

FROM php:${PHP_VERSION}-fpm

ARG TARGETARCH

# renovate: datasource=github-releases depName=just-containers/s6-overlay extractVersion=^v(?<version>.+)$
ARG S6_OVERLAY_VERSION=3.2.3.2
ARG S6_OVERLAY_NOARCH_SHA256=5379750ed30a84bbd2e2dd74847ba6b5bd29cd0b2e3ea2ec58049b57eb2eda12
ARG S6_OVERLAY_X86_64_SHA256=e6befcc96a437a3831386ecfc51808c5d3e939dc5fe3c02ae9284599e8aa2408
ARG S6_OVERLAY_AARCH64_SHA256=b17f17a82e7a515c682a91edaf2ffdabb73f891981b6c1fd712115693a2f8b4c

# renovate: datasource=github-releases depName=aptible/supercronic extractVersion=^v(?<version>.+)$
ARG SUPERCRONIC_VERSION=0.2.51
ARG SUPERCRONIC_AMD64_SHA256=cc232108374e8e2b537045f2d5eaa1229f619db314c3ba6a14d38b35dc0aa123
ARG SUPERCRONIC_ARM64_SHA256=4ae22576a78223d8ccdf5f3b3660a5cbb5288416bf0ca96afc4a36d195932b94

COPY --from=mlocati/php-extension-installer:2.12.3 /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=composer:2.10.3 /usr/bin/composer /usr/local/bin/composer

# s6-overlay (process supervision) and supercronic (cron)
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) s6_arch=x86_64; s6_sha="$S6_OVERLAY_X86_64_SHA256"; cron_sha="$SUPERCRONIC_AMD64_SHA256" ;; \
      arm64) s6_arch=aarch64; s6_sha="$S6_OVERLAY_AARCH64_SHA256"; cron_sha="$SUPERCRONIC_ARM64_SHA256" ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    s6_url="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}"; \
    curl -fsSLo /tmp/s6-noarch.tar.xz "$s6_url/s6-overlay-noarch.tar.xz"; \
    curl -fsSLo /tmp/s6-arch.tar.xz "$s6_url/s6-overlay-${s6_arch}.tar.xz"; \
    echo "$S6_OVERLAY_NOARCH_SHA256  /tmp/s6-noarch.tar.xz" | sha256sum -c -; \
    echo "$s6_sha  /tmp/s6-arch.tar.xz" | sha256sum -c -; \
    tar -C / -Jxpf /tmp/s6-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-arch.tar.xz; \
    curl -fsSLo /usr/local/bin/supercronic \
      "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-${TARGETARCH}"; \
    echo "$cron_sha  /usr/local/bin/supercronic" | sha256sum -c -; \
    chmod +x /usr/local/bin/supercronic; \
    rm -f /tmp/s6-*.tar.xz

# Debian security updates (without waiting for the upstream image to be
# rebuilt), Apache, tools and PHP extensions
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; \
    apt-get install -y --no-install-recommends apache2 git unzip zip; \
    rm -rf /var/lib/apt/lists/*; \
    install-php-extensions pdo_mysql mysqli intl zip gd opcache apcu; \
    mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    rm -f /var/www/html/index.html; \
    ln -sfT /dev/stderr /var/log/apache2/error.log; \
    ln -sfT /dev/stdout /var/log/apache2/access.log; \
    ln -sfT /dev/stdout /var/log/apache2/other_vhosts_access.log; \
    mkdir -p /etc/supercronic /docker-entrypoint.d

ENV APACHE_DOCUMENT_ROOT=/var/www/html \
    CRONTAB=/etc/supercronic/crontab \
    PHP_MEMORY_LIMIT=128M \
    PHP_UPLOAD_MAX_FILESIZE=2M \
    PHP_POST_MAX_SIZE=8M \
    PHP_MAX_EXECUTION_TIME=30 \
    PHP_OPCACHE_MEMORY=128 \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=0 \
    PHP_APCU_MEMORY=32M \
    PHP_FPM_PM=ondemand \
    PHP_FPM_MAX_CHILDREN=10 \
    PHP_FPM_START_SERVERS=2 \
    PHP_FPM_MIN_SPARE_SERVERS=1 \
    PHP_FPM_MAX_SPARE_SERVERS=3 \
    PHP_FPM_PROCESS_IDLE_TIMEOUT=10s \
    PHP_FPM_MAX_REQUESTS=500 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_SERVICES_GRACETIME=25000 \
    S6_KILL_GRACETIME=3000 \
    S6_VERBOSITY=1

COPY rootfs/ /

RUN set -eux; \
    a2dismod -f mpm_prefork 2>/dev/null || true; \
    a2enmod mpm_event proxy_fcgi setenvif headers rewrite; \
    a2disconf security other-vhosts-access-log; \
    a2enconf php-parent; \
    a2dissite 000-default; \
    a2ensite app; \
    apache2ctl -t

EXPOSE 80
# The official FPM image stops with SIGQUIT; s6-overlay and commands expect SIGTERM
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s CMD ["healthcheck"]

ENTRYPOINT ["docker-entrypoint"]
CMD ["web"]
