#!/bin/bash

# Gen environment file to swap mainnet/testnet
echo "" > /mnt/hdd/mynode/pool/env
if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
    echo "NETWORK=testnet" >> /mnt/hdd/mynode/pool/env
else
    echo "NETWORK=mainnet" >> /mnt/hdd/mynode/pool/env
fi
chown bitcoin:bitcoin /mnt/hdd/mynode/pool/env