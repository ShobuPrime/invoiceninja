FROM alpine:latest

ARG OVERLAY_VERSION="v2.0.0.1"
ARG OVERLAY_ARCH="amd64"
ENV INVOICENINJA_VERSION 5.0.12

RUN \
    apk add --no-cache \
	curl && \
    curl \
	-o /tmp/s6-overlay.tar.gz \
	-L "https://github.com/just-containers/s6-overlay/releases/download/$OVERLAY_VERSION/s6-overlay-$OVERLAY_ARCH.tar.gz" && \
    tar xfz /tmp/s6-overlay.tar.gz -C / && \
	rm -rf /tmp/*

#install packages
RUN \
    apk add --no-cache \
	nginx \
	libressl \
	php \
	php-fpm \
	php-fileinfo \
	php-json \
	php-mbstring \
	php-openssl \
	php-session \
	php-simplexml \
	php-xml \
	php-xmlwriter \
	php-xmlreader \
	php-cli \
	php-ctype \
	php-curl \
	php-dom \
	php-gd \
	php-gmp \
	php-iconv \
	php-pdo_mysql \
	php-phar \
	php-tokenizer \
	php-zip && \
    rm /etc/nginx/conf.d/default.conf && \
    mkdir -p /run/nginx && \
    mkdir -p /var/tmp/nginx


#Get Invoice Ninja
RUN \
    apk add --no-cache --virtual=build-deps \
	curl && \
    curl -o /tmp/ninja.tar.gz -L "https://github.com/invoiceninja/invoiceninja/archive/v{$INVOICENINJA_VERSION}.tar.gz" && \
	tar xfz /tmp/ninja.tar.gz -C /tmp/ && \
	mv /tmp/invoiceninja-${INVOICENINJA_VERSION} /app && \
    apk del --purge build-deps && \
    rm -rf /tmp/*


# install php dependencies via composer
RUN \
    cd /app && \
	curl -sS https://getcomposer.org/installer | php && \
	mv composer.phar /usr/bin/composer && \
    composer install --no-dev -o && \
\
    rm -rf /usr/bin/composer && \
    rm -rf ~/.composer && \
    rm -rf /tmp/*


RUN \
    apk add --no-cache \
	shadow && \
    groupmod -g 1000 users && \
	useradd -u 911 -U -d /app -s /bin/false abc && \
	usermod -G users abc

ENV APP_KEY=SomeRandomStringSomeRandomString
ENV APP_URL=https://www.ninja.test

ENV DB_HOST=localhost
ENV DB_DATABASE=invoiceninja
ENV DB_USERNAME=ninja
ENV DB_PASSWORD=ninjapasswd

#COPY root/ /

#VOLUME ["/app/storage","/app/public/logo"]
EXPOSE 80

ENTRYPOINT ["/init"]
