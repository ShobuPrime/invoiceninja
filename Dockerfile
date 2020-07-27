ARG PHP_VERSION=7.3

# Get Invoice Ninja
FROM alpine:latest as base
ARG INVOICENINJA_VERSION=5.0.12

RUN set -eux; \
    apk add --no-cache \
    curl \
    libarchive-tools; \
    mkdir -p /var/www/app

RUN curl -o /tmp/ninja.tar.gz -LJ0 https://github.com/invoiceninja/invoiceninja/tarball/v$INVOICENINJA_VERSION \
    && bsdtar --strip-components=1 -C /var/www/app -xf /tmp/ninja.tar.gz \
    && rm /tmp/ninja.tar.gz \
    && cp -R /var/www/app/storage /var/www/app/docker-backup-storage  \
    && cp -R /var/www/app/public /var/www/app/docker-backup-public  \
    && mkdir -p /var/www/app/public/logo /var/www/app/storage \
    && cp /var/www/app/.env.example /var/www/app/.env \
    && cp /var/www/app/.env.dusk.example /var/www/app/.env.dusk.local \
    && rm -rf /var/www/app/docs /var/www/app/tests

# Install nodejs packages
FROM node:current-alpine as frontend

COPY --from=base /var/www/app /var/www/app
WORKDIR /var/www/app/

RUN apk add --update nodejs npm

# Prepare php image
FROM php:${PHP_VERSION}-fpm-alpine
ARG INVOICENINJA_VERSION
ENV INVOICENINJA_VERSION=$INVOICENINJA_VERSION

LABEL maintainer="ShobuPrime"

WORKDIR /var/www/app

COPY --from=frontend /var/www/app /var/www/app
COPY entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

RUN set -eux; \
    apk add --no-cache \
    freetype-dev \
    gmp-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libzip-dev; \
    docker-php-ext-configure zip --with-libzip; \
    docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ --with-png-dir=/usr/include/; \
    docker-php-ext-install -j$(nproc) \
        bcmath \
        exif \
        gd \
        gmp \
        mbstring \
        mysqli \
        opcache \
        pdo \
        pdo_mysql \
        zip

COPY ./config/php/php.ini /usr/local/etc/php/php.ini
COPY ./config/php/php-cli.ini /usr/local/etc/php/php-cli.ini

## Separate user
ENV INVOICENINJA_USER=invoiceninja

RUN addgroup -S "$INVOICENINJA_USER" && \
    adduser \
    #--disabled-password \
    --password "$INVOICENINJA_USER" \
    --gecos "" \
    --home "$(pwd)" \
    --ingroup "$INVOICENINJA_USER" \ 
    --no-create-home \
    "$INVOICENINJA_USER"; \
    addgroup "$INVOICENINJA_USER" www-data; \
    chown -R "$INVOICENINJA_USER":"$INVOICENINJA_USER" /var/www/app

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer; \
    composer global require hirak/prestissimo;
    
RUN apk add --no-cache su-exec
RUN set -ex && apk --no-cache add sudo

USER $INVOICENINJA_USER

RUN composer install --no-dev --no-suggest --no-progress

# Override the environment settings from projects .env file
ENV APP_ENV production
ENV LOG errorlog

ENTRYPOINT ["docker-entrypoint"]
CMD ["php-fpm"]
