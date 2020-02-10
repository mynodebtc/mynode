#!/bin/bash

set -e
set -x

while true; do
    logrotate /etc/logrotate.conf
    sleep 10m
done

# We should not exit
exit 1
