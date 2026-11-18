#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

WALLET_FOLDER="/mnt/hdd/mynode/bitcoin"
if [ -f $IS_TESTNET_ENABLED_FILE ]; then
    WALLET_FOLDER="/mnt/hdd/mynode/bitcoin/testnet3/wallets"
fi

sleep 60s

# Give admin a copy of the BTC cookie
chmod 600 /mnt/hdd/mynode/bitcoin/.cookie
install -m 600 -o admin -g admin /mnt/hdd/mynode/bitcoin/.cookie /home/admin/.bitcoin/.cookie

if [ -f /mnt/hdd/mynode/bitcoin/testnet3/.cookie ]; then
    mkdir -p /mnt/hdd/mynode/bitcoin/testnet3
    chmod 600 /mnt/hdd/mynode/bitcoin/testnet3/.cookie
    mkdir -p /home/admin/.bitcoin/testnet3
    install -m 600 -o admin -g admin /mnt/hdd/mynode/bitcoin/testnet3/.cookie /home/admin/.bitcoin/testnet3/.cookie
    chown admin:admin /home/admin/.bitcoin/testnet3
fi

# Make data folders readable for easier transfer between nodes (new files are still 700)
#chmod -R 755 /mnt/hdd/mynode/bitcoin/blocks || true
#chmod -R 755 /mnt/hdd/mynode/bitcoin/chainstate || true
#chmod -R 755 /mnt/hdd/mynode/bitcoin/indexes || true

# Sync FS
sync