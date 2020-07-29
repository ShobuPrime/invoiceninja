ARG PHP_VERSION=7.3.19

# Get Invoice Ninja
FROM alpine:latest as base
ARG INVOICENINJA_VERSION=4.5.19

RUN set -eux; \
    apk update \
    && apk add --no-cache \
    curl \
    libarchive-tools; \
    mkdir -p /var/www/app
    
RUN cd /usr/share \
    && curl  -L https://github.com/Overbryd/docker-phantomjs-alpine/releases/download/2.11/phantomjs-alpine-x86_64.tar.bz2 | tar xj \
    && ln -s /usr/share/phantomjs/phantomjs /usr/local/bin/phantomjs

RUN curl -o /tmp/ninja.tar.gz -LJ0 https://github.com/invoiceninja/invoiceninja/tarball/v$INVOICENINJA_VERSION \
    && bsdtar --strip-components=1 -C /var/www/app -xf /tmp/ninja.tar.gz \
    && rm /tmp/ninja.tar.gz \
    && cp -R /var/www/app/storage /var/www/app/docker-backup-storage  \
    && cp -R /var/www/app/public /var/www/app/docker-backup-public  \
    && mkdir -p /var/www/app/public/logo /var/www/app/storage \
    && cp /var/www/app/.env.example /var/www/app/.env \
    && chmod -R 755 /var/www/app/storage  \
    && rm -rf /var/www/app/docs /var/www/app/tests

# Install nodejs packages
FROM node:current-alpine as frontend

COPY --from=base /var/www/app /var/www/app
WORKDIR /var/www/app

# Prepare php image
FROM php:${PHP_VERSION}-fpm-alpine
ARG INVOICENINJA_VERSION
ENV INVOICENINJA_VERSION=$INVOICENINJA_VERSION

LABEL maintainer="ShobuPrime"

WORKDIR /var/www/app

COPY --from=frontend /var/www/app /var/www/app
COPY entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint


#####
# SYSTEM REQUIREMENT
#####
ENV PHANTOMJS phantomjs-2.1.1-linux-x86_64

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=60'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
} > /usr/local/etc/php/conf.d/opcache-recommended.ini

ENV PHANTOMJS_BIN_PATH /usr/local/bin/phantomjs

RUN apk update \
    && apk add --no-cache git \
    coreutils \
    chrpath \
    fontconfig \
    libpng-dev

RUN set -eux; \
    apk add --no-cache \
    freetype-dev \
    gmp-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libzip-dev \
    # https://github.com/docker-library/php/pull/840#issuecomment-502262726
    oniguruma-dev;

RUN apk add --no-cache zip
RUN docker-php-ext-install zip
RUN docker-php-ext-configure zip

RUN docker-php-ext-configure gd --with-freetype --with-jpeg
RUN docker-php-ext-install bcmath \
    exif \
    gd \
    gmp \
    # mbstring fails with 7.4
    # Reason: https://stackoverflow.com/questions/59251008/docker-laravel-configure-error-package-requirements-oniguruma-were-not-m/59253249#59253249
    mbstring \
    mysqli \
    opcache \
    pdo \
    pdo_mysql;

COPY ./config/php/php.ini /usr/local/etc/php/php.ini
COPY ./config/php/php-cli.ini /usr/local/etc/php/php-cli.ini

## Separate user
ENV INVOICENINJA_USER=invoiceninja

RUN addgroup -S "$INVOICENINJA_USER" && \
    adduser \
    --disabled-password \
    #--password "temp" \
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
    
# Official docker image does not seem to have Node.js running properly in the container
# Brute force it!
RUN apk add --no-cache \
    nodejs \
    npm \
    nodejs-npm;

# InvoiceNinja Self-Host troubleshooting mentions to try this: https://invoiceninja.github.io/selfhost.html#trouble-shooting
#ENV NODE_PATH=/usr/bin
#ENV NPM_PATH=/usr/bin

# "Test PDF" option is failing.
# Log used to mention "Error: Cannot find module 'puppeteer'"
# Install puppeteer so it's available in the container.
RUN npm i puppeteer
    # Add user so we don't need --no-sandbox.
    # same layer as npm install to keep re-chowned files from using up several hundred MBs more space
    #&& groupadd -r pptruser && useradd -r -g pptruser -G audio,video pptruser \
    #&& mkdir -p /home/pptruser/Downloads \
    #&& chown -R pptruser:pptruser /home/pptruser \
    #&& chown -R pptruser:pptruser /node_modules

# Puppeteer will fail with: "Error: Failed to launch chrome! spawn /var/www/app/node_modules/puppeteer/.local-chromium/linux-686378/chrome-linux/chrome ENOENT"
# Attempting fixes found in: https://github.com/puppeteer/puppeteer/blob/main/docs/troubleshooting.md#running-puppeteer-in-docker
#-----------------
# Installs latest Chromium (77) package.
RUN apk add --no-cache \
        chromium \
        nss \
        freetype \
        freetype-dev \
        harfbuzz \
        ca-certificates \
        ttf-freefont \
        yarn
     
# Tell Puppeteer to skip installing Chrome. We'll be using the installed package.
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
    
# Puppeteer v1.19.0 works with Chromium 77.
RUN yarn add puppeteer@1.19.0

#RUN apk install gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget

USER $INVOICENINJA_USER

RUN composer install --no-dev --no-suggest --no-progress

# Override the environment settings from projects .env file
ENV APP_ENV production
ENV LOG errorlog

ENTRYPOINT ["docker-entrypoint"]
CMD ["php-fpm"]
