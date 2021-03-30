#!/bin/bash

source /usr/share/mynode/mynode_config.sh

NETWORK=mainnet
if [ -f $IS_TESTNET_ENABLED_FILE ]; then
    NETWORK=testnet
fi

# Wait until lnd is synced
echo "Checking if LND is synced..."
lncli --network=$NETWORK --lnddir /mnt/hdd/mynode/lnd getinfo | grep 'synced_to_chain": true'
while [ ! $? ]; do
    echo "LND not synced, sleeping for 60 seconds..."
    /bin/sleep 60s
    lncli --network=$NETWORK --lnddir /mnt/hdd/mynode/lnd getinfo | grep 'synced_to_chain": true'
done
exit 0