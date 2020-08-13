#!/bin/bash

set -x
set -e

# Check for dhparam on SD Card
if [ ! -f /etc/ssl/certs/dhparam.pem ]; then
    # Check for dhparam on HDD
    if [ -f /mnt/hdd/mynode/settings/dhparam.pem ]; then
        echo "Using dhparam.pem from HDD"
        cp -f /mnt/hdd/mynode/settings/dhparam.pem /etc/ssl/certs/dhparam.pem
    else
        # Gen dhparam
        echo "Generating dhparam.pem"
        time openssl dhparam -out /tmp/dhparam.pem 2048
        cp -f /tmp/dhparam.pem /etc/ssl/certs/dhparam.pem
        cp -f /tmp/dhparam.pem /mnt/hdd/mynode/settings/dhparam.pem
    fi
    sync
else
    echo "dharam.pem already created"
fi

# If not on HDD, make backup copy
if [ ! -f /mnt/hdd/mynode/settings/dhparam.pem ]; then
    cp -f /etc/ssl/certs/dhparam.pem /mnt/hdd/mynode/settings/dhparam.pem
fi