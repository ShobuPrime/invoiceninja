FROM invoiceninja/invoiceninja:latest

USER root

RUN apk update
RUN node install
RUN npm install

USER invoiceninja

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
