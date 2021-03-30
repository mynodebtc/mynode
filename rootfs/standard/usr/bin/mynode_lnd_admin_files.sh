#!/bin/bash

source /usr/share/mynode/mynode_config.sh

NETWORK=mainnet
if [ -f $IS_TESTNET_ENABLED_FILE ]; then
    NETWORK=testnet
fi

mkdir -p /home/admin/.lnd/
mkdir -p /home/admin/.lnd/data/chain/bitcoin/$NETWORK/
chown -R admin:admin /home/admin/.lnd/

echo "Waiting on lnd files..."
while [ ! -f $LND_TLS_CERT_FILE ]; do
    sleep 1m
done
# Copy cert so we can interact with LND even if wallet has not been created
cp -f $LND_TLS_CERT_FILE /home/admin/.lnd/
chown -R admin:admin /home/admin/.lnd/
while [ ! -f $LND_ADMIN_MACAROON_FILE ]; do
    sleep 1m
done
echo "LND files found!"

while true; do
    # Make sure lnd path exists for admin user
    mkdir -p /home/admin/.lnd/
    mkdir -p /home/admin/.lnd/data/chain/bitcoin/$NETWORK/
    chown -R admin:admin /home/admin/.lnd/

    # Copy LND files to admin folder
    cp -f $LND_TLS_CERT_FILE /home/admin/.lnd/
    cp -f /mnt/hdd/mynode/lnd/data/chain/bitcoin/$NETWORK/*.macaroon /home/admin/.lnd/data/chain/bitcoin/$NETWORK/
    chown -R admin:admin /home/admin/.lnd/
    echo "Updated admin copy of LND files!"

    # Wait for changes
    inotifywait -e modify -e create -e delete $LND_TLS_CERT_FILE /mnt/hdd/mynode/lnd/data/chain/bitcoin/$NETWORK/*.macaroon
done

# Should never exit
exit 99