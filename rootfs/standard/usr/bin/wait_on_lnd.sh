#!/bin/bash

# Wait until lnd is synced
echo "Checking if LND is synced..."
lncli --lnddir /mnt/hdd/mynode/lnd getinfo | grep 'synced_to_chain": true'
while [ ! $? ]; do
    echo "LND not synced, sleeping for 60 seconds..."
    /bin/sleep 60s
    lncli --lnddir /mnt/hdd/mynode/lnd getinfo | grep 'synced_to_chain": true'
done
exit 0