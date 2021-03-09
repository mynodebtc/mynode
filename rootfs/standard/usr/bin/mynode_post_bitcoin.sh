#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

sleep 60s

# Give admin the ability to access the BTC cookie
cp -f /mnt/hdd/mynode/bitcoin/.cookie /home/admin/.bitcoin/.cookie
chown admin:admin /home/admin/.bitcoin/.cookie

if [ -f /mnt/hdd/mynode/bitcoin/testnet3/.cookie ]; then
    mkdir -p /mnt/hdd/mynode/bitcoin/testnet3
    cp -f /mnt/hdd/mynode/bitcoin/testnet3/.cookie /home/admin/.bitcoin/testnet3/.cookie
    chown -R admin:admin /home/admin/.bitcoin/testnet3
fi

# Make default wallets
bitcoin-cli createwallet joinmarket_wallet.dat > /dev/null  2>&1 || true
bitcoin-cli loadwallet joinmarket_wallet.dat > /dev/null  2>&1 || true

# Sync FS
sync