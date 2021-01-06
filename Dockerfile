ARG PHP_VERSION=8.0

# Get Invoice Ninja
FROM alpine:latest as base
ARG INVOICENINJA_VERSION=5.0.43

RUN set -eux; \
    apk update \
    && apk add --no-cache \
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

#RUN set -eux; \
#    apk add --no-cache \
#    freetype-dev \
#    gmp-dev \
#    libjpeg-turbo-dev \
#    libpng-dev \
#    libzip-dev; \
#    # While initially copying the following line from official Dockerfile, this worked with PHP7.3. It fails with 7.4
#    # The following issue mentions it's safe to disable: https://github.com/laradock/laradock/issues/2407
#    # https://github.com/laradock/laradock/issues/2414
#    # docker-php-ext-configure zip --with-libzip; \
#    # Just like the command above, this step also fails while trying to upgrade from 7.3 to 7.4 in this image
#    # Solution was found here: https://github.com/docker-library/php/issues/912#issuecomment-559918036
#    # docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ --with-png-dir=/usr/include/; \
#    docker-php-ext-configure gd --with-freetype --with-jpeg \
#    # docker-php-ext-install -j$(nproc) \
#    docker-php-ext-install \
#        bcmath \
#        exif \
#        gd \
#        gmp \
#        mbstring \
#        mysqli \
#        opcache \
#        pdo \
#        pdo_mysql \
#        zip
        
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
#RUN npm i puppeteer
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
#RUN apk add --no-cache \
#        chromium \
#        nss \
#        freetype \
#        freetype-dev \
#        harfbuzz \
#        ca-certificates \
#        ttf-freefont \
#        yarn
     
# Tell Puppeteer to skip installing Chrome. We'll be using the installed package.
#ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
#    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
    
# Puppeteer v1.19.0 works with Chromium 77.
#RUN yarn add puppeteer@1.19.0

#RUN apk install gconf-service libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget

# Started a conversation on InvoiceNinja forums to sort out the PDF errors
# https://forum.invoiceninja.com/t/fresh-v5-docker-install-500-server-error-and-production-info-db-fails/4394/4
RUN echo 'kernel.unprivileged_userns_clone=1' > /etc/sysctl.d/userns.conf

USER $INVOICENINJA_USER

RUN composer install --no-dev --no-suggest --no-progress

# Override the environment settings from projects .env file
ENV APP_ENV production
ENV LOG errorlog

ENTRYPOINT ["docker-entrypoint"]
CMD ["php-fpm"]
