FROM invoiceninja/invoiceninja:latest

USER root

#I keep hetting 500 server errors and npm not found in official docker image
RUN apk update \
    && add --update nodejs npm \
    && add --update npm

USER invoiceninja

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
