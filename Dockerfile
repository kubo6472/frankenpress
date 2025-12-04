# =============================================================================
# FrankenPress - Optimized WordPress Docker Image (Fixed Version)
# =============================================================================

ARG WORDPRESS_VERSION=latest
ARG PHP_VERSION=8.3
ARG FRANKENPHP_VERSION=1.10.1
ARG DEBIAN_VERSION=trixie

# -----------------------------------------------------------------------------
# Stage 1: WordPress Source Files
# -----------------------------------------------------------------------------
FROM public.ecr.aws/docker/library/wordpress:$WORDPRESS_VERSION AS wp

# -----------------------------------------------------------------------------
# Stage 2: Final FrankenPress Image
# -----------------------------------------------------------------------------
FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php${PHP_VERSION}-${DEBIAN_VERSION} AS base

LABEL org.opencontainers.image.title="FrankenPress" \
      org.opencontainers.image.description="Optimized WordPress containers to run everywhere. Built with FrankenPHP & Caddy." \
      org.opencontainers.image.source="https://github.com/notglossy/frankenpress" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Not Glossy"

ENV FORCE_HTTPS=0 \
    PHP_INI_SCAN_DIR=$PHP_INI_DIR/conf.d \
    PAGER=more

# -----------------------------------------------------------------------------
# Dependencies + PHP Extensions
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates ghostscript curl unzip git \
    libonig-dev libxml2-dev libcurl4-openssl-dev libssl-dev libzip-dev \
    libjpeg-dev libwebp-dev zlib1g-dev \
    && install-php-extensions \
        bcmath exif gd intl mysqli zip imagick \
        opcache memcache memcached apcu redis igbinary msgpack \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
        libonig-dev libxml2-dev libcurl4-openssl-dev libssl-dev libzip-dev \
        libjpeg-dev libwebp-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* /usr/share/man/*

# -----------------------------------------------------------------------------
# PHP Configuration
# -----------------------------------------------------------------------------
RUN cp $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini \
 && { \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.interned_strings_buffer=8'; \
        echo 'opcache.max_accelerated_files=4000'; \
        echo 'opcache.revalidate_freq=2'; \
    } > $PHP_INI_DIR/conf.d/opcache-recommended.ini \
 && { \
        echo 'error_reporting=E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
        echo 'display_errors=Off'; \
        echo 'display_startup_errors=Off'; \
        echo 'log_errors=On'; \
        echo 'error_log=/dev/stderr'; \
        echo 'log_errors_max_len=1024'; \
        echo 'ignore_repeated_errors=On'; \
        echo 'ignore_repeated_source=Off'; \
        echo 'html_errors=Off'; \
    } > $PHP_INI_DIR/conf.d/error-logging.ini \
 && echo 'expose_php=Off' > $PHP_INI_DIR/conf.d/expose_php.ini

# -----------------------------------------------------------------------------
# WP-CLI
# -----------------------------------------------------------------------------
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
 && chmod +x wp-cli.phar \
 && mv wp-cli.phar /usr/local/bin/wp

# -----------------------------------------------------------------------------
# WordPress Core & Entrypoint Copy
# -----------------------------------------------------------------------------
COPY --from=wp /usr/src/wordpress /usr/src/wordpress
COPY --from=wp /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d/
COPY --from=wp /usr/local/bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# -----------------------------------------------------------------------------
# Modify Entrypoint / wp-config for FrankenPHP
# -----------------------------------------------------------------------------
RUN sed -i \
        -e 's/\[ "$1" = '\''php-fpm'\'' \]/\[\[ "$1" == frankenphp* \]\]/g' \
        -e 's/php-fpm/frankenphp/g' \
        /usr/local/bin/docker-entrypoint.sh \
    && sed -i \
        's/<?php/<?php if (!!getenv("FORCE_HTTPS")) { \$_SERVER["HTTPS"]="on"; } define("FS_METHOD","direct"); set_time_limit(300); /' \
        /usr/src/wordpress/wp-config-docker.php

# -----------------------------------------------------------------------------
# Custom Configs (last for caching)
# -----------------------------------------------------------------------------
COPY php.ini $PHP_INI_DIR/conf.d/wp.ini
COPY Caddyfile /etc/caddy/Caddyfile

# -----------------------------------------------------------------------------
# Create User (if needed)
# -----------------------------------------------------------------------------
ARG USER_NAME=www-data
RUN if id "$USER_NAME" &>/dev/null; then echo "User exists"; else useradd -m $USER_NAME; fi \
 && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp

# -----------------------------------------------------------------------------
# Declare the volume BEFORE fixing ownership
# -----------------------------------------------------------------------------
VOLUME /var/www/html

# Now fix permissions for the runtime mount
RUN chown -R ${USER_NAME}:${USER_NAME} /var/www/html \
    /data/caddy \
    /config/caddy \
    /usr/src/wordpress \
    /usr/local/bin/docker-entrypoint.sh

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------
WORKDIR /var/www/html
USER $USER_NAME

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
