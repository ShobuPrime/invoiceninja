FROM invoiceninja/invoiceninja:latest

RUN apk update
RUN node install
RUN npm install

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
