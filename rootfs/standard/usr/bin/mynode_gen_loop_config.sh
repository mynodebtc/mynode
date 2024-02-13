#!/bin/bash

# Gen environment file to swap mainnet/testnet
echo "" > /mnt/hdd/mynode/loop/env
if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
    echo "NETWORK=testnet"                                                                          >> /mnt/hdd/mynode/loop/env
    echo "LND_ADMIN_MACAROON_PATH=/mnt/hdd/mynode/lnd/data/chain/bitcoin/testnet/admin.macaroon"    >> /mnt/hdd/mynode/loop/env
else
    echo "NETWORK=mainnet"                                                                          >> /mnt/hdd/mynode/loop/env
    echo "LND_ADMIN_MACAROON_PATH=/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon"    >> /mnt/hdd/mynode/loop/env
fi
chown bitcoin:bitcoin /mnt/hdd/mynode/loop/env

# Copy config file
cp -f /usr/share/mynode/loopd.conf /mnt/hdd/mynode/loop/loopd.conf
chown bitcoin:bitcoin /mnt/hdd/mynode/loop/loopd.conf
