#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x
set -e

# Setup electrs
cp -f /usr/share/mynode/electrs.toml /mnt/hdd/mynode/electrs/electrs.toml

# Update for testnet
if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
    sed -i "s/bitcoin/testnet/g" /mnt/hdd/mynode/electrs/electrs.toml || true
else
    sed -i "s/testnet/bitcoin/g" /mnt/hdd/mynode/electrs/electrs.toml || true
fi

# Update for tx limit
INDEX_LOOKUP_LIMIT=200
if [ $IS_X86 = 1 ]; then
    INDEX_LOOKUP_LIMIT=1000
fi
if [ -f /mnt/hdd/mynode/electrs/index_lookup_limit ]; then
    INDEX_LOOKUP_LIMIT=$(cat /mnt/hdd/mynode/electrs/index_lookup_limit)
fi
if [ ! -f /mnt/hdd/mynode/electrs/index_lookup_limit ]; then
    echo "$INDEX_LOOKUP_LIMIT" > /mnt/hdd/mynode/electrs/index_lookup_limit
fi
sed -i "s/index_lookup_limit =.*/index_lookup_limit = $INDEX_LOOKUP_LIMIT/g" /mnt/hdd/mynode/electrs/electrs.toml || true


# Remove old electrs data (pre-v9)
rm -rf /mnt/hdd/mynode/electrs/mainnet

# Use correct binary on RP4 (32 bit/64bit)
if [ $IS_RASPI4 -eq 1 ] || [ $IS_RASPI5 -eq 1 ]; then
    ELECTRS_DST=/usr/bin/electrs
    ELECTRS_SRC=/usr/bin/electrs_arm32
    if [ $IS_ARM64 -eq 1 ]; then
        ELECTRS_SRC=/usr/bin/electrs_arm64
    fi
    if [ ! -f $ELECTRS_DST ]; then
        cp -f $ELECTRS_SRC $ELECTRS_DST
    else
        MD5_1=$(md5sum $ELECTRS_DST | cut -d' ' -f 1)
        MD5_2=$(md5sum $ELECTRS_SRC | cut -d' ' -f 1)
        if [ "${MD5_1}" != "{$MD5_2}" ]; then
            cp -f $ELECTRS_SRC $ELECTRS_DST
        fi
    fi
fi

chown -R bitcoin:bitcoin /mnt/hdd/mynode/electrs

sync
sleep 3s