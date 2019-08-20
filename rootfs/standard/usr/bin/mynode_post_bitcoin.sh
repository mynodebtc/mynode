#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

sleep 60s

# Give admin the ability to access the BTC cookie
cp -f /mnt/hdd/mynode/bitcoin/.cookie /home/admin/.bitcoin/.cookie
chown admin:admin /home/admin/.bitcoin/.cookie

# Sync FS
sync