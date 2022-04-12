#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

WALLET_FOLDER="/mnt/hdd/mynode/bitcoin"
if [ -f $IS_TESTNET_ENABLED_FILE ]; then
    WALLET_FOLDER="/mnt/hdd/mynode/bitcoin/testnet3/wallets"
fi

sleep 60s

# Give admin the ability to access the BTC cookie
chmod 640 /mnt/hdd/mynode/bitcoin/.cookie
cp -f /mnt/hdd/mynode/bitcoin/.cookie /home/admin/.bitcoin/.cookie
chown admin:admin /home/admin/.bitcoin/.cookie

if [ -f /mnt/hdd/mynode/bitcoin/testnet3/.cookie ]; then
    mkdir -p /mnt/hdd/mynode/bitcoin/testnet3
    cp -f /mnt/hdd/mynode/bitcoin/testnet3/.cookie /home/admin/.bitcoin/testnet3/.cookie
    chown -R admin:admin /home/admin/.bitcoin/testnet3
fi

# Make data folders readable for easier transfer between nodes (new files are still 700)
#chmod -R 755 /mnt/hdd/mynode/bitcoin/blocks || true
#chmod -R 755 /mnt/hdd/mynode/bitcoin/chainstate || true
#chmod -R 755 /mnt/hdd/mynode/bitcoin/indexes || true

# Sync FS
sync