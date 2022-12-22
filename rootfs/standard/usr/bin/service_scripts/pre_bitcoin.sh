#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

# Try to migrate wallet.dat
if [ -f /mnt/hdd/mynode/bitcoin/wallet.dat ]; then
    mkdir -p /mnt/hdd/mynode/bitcoin/wallet_folder.dat
    mv /mnt/hdd/mynode/bitcoin/wallet.dat /mnt/hdd/mynode/bitcoin/wallet_folder.dat/wallet.dat
    mv /mnt/hdd/mynode/bitcoin/wallet_folder.dat /mnt/hdd/mynode/bitcoin/wallet.dat
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/bitcoin/wallet.dat
fi

rm -f /mnt/hdd/mynode/bitcoin/settings.json

# Sync FS
sync