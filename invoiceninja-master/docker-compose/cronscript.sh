#!/bin/bash

bash -c 'bash -s <<EOF
trap "break;exit" SIGHUP SIGINT SIGTERM
sleep 300s
while /bin/true; do
      ./artisan ninja:send-invoices
      ./artisan ninja:send-reminders
      sleep 1d
done
EOF'
