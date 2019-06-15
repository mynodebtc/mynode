#!/bin/bash

source /usr/share/mynode/mynode_config.sh

mkdir -p /home/admin/.lnd/
mkdir -p /home/admin/.lnd/data/chain/bitcoin/mainnet/
chown -R admin:admin /home/admin/.lnd/

echo "Waiting on lnd files..."
while [ ! -f $LND_TLS_CERT_FILE ]; do
    sleep 1m
done
while [ ! -f $LND_ADMIN_MACAROON_FILE ]; do
    sleep 1m
done
echo "LND files found!"

while true; do
    # Make sure lnd admin path exists
    mkdir -p /home/admin/.lnd/
    mkdir -p /home/admin/.lnd/data/chain/bitcoin/mainnet/
    chown -R admin:admin /home/admin/.lnd/

    # Copy LND files to admin folder
    cp -f $LND_TLS_CERT_FILE /home/admin/.lnd/
    cp -f $LND_ADMIN_MACAROON_FILE /home/admin/.lnd/data/chain/bitcoin/mainnet/admin.macaroon
    chown -R admin:admin /home/admin/.lnd/
    echo "Updated admin copy of LND files!"

    # Wait for changes
    inotifywait -e modify -e create -e delete $LND_TLS_CERT_FILE $LND_ADMIN_MACAROON_FILE
done

# Should never exit
exit 99