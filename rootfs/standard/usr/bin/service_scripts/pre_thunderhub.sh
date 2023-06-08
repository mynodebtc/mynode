#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x
set -e

# Thunderhub config
mkdir -p /mnt/hdd/mynode/thunderhub/
if [ ! -f /mnt/hdd/mynode/thunderhub/.env.local ]; then
    cp -f /usr/share/mynode/thunderhub.env /mnt/hdd/mynode/thunderhub/.env.local
fi
if [ ! -f /mnt/hdd/mynode/thunderhub/thub_config.yaml ]; then
    cp -f /usr/share/mynode/thub_config.yaml /mnt/hdd/mynode/thunderhub/thub_config.yaml
fi
THUNDERHUB_CONFIG_UPDATE_NUM=1
if [ ! -f /mnt/hdd/mynode/thunderhub/update_settings_$THUNDERHUB_CONFIG_UPDATE_NUM ]; then
    cp -f /usr/share/mynode/thunderhub.env /mnt/hdd/mynode/thunderhub/.env.local
    cp -f /usr/share/mynode/thub_config.yaml /mnt/hdd/mynode/thunderhub/thub_config.yaml
    touch /mnt/hdd/mynode/thunderhub/update_settings_$THUNDERHUB_CONFIG_UPDATE_NUM
fi
if [ -f /mnt/hdd/mynode/thunderhub/thub_config.yaml ]; then
    if [ -f /home/bitcoin/.mynode/.hashedpw_bcrypt ]; then
        HASH_BCRYPT=$(cat /home/bitcoin/.mynode/.hashedpw_bcrypt)
        sed -i "s#masterPassword:.*#masterPassword: \"thunderhub-$HASH_BCRYPT\"#g" /mnt/hdd/mynode/thunderhub/thub_config.yaml
    fi
    if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
        sed -i "s/mainnet/testnet/g" /mnt/hdd/mynode/thunderhub/thub_config.yaml || true
    else
        sed -i "s/testnet/mainnet/g" /mnt/hdd/mynode/thunderhub/thub_config.yaml || true
    fi
fi

chown -R bitcoin:bitcoin /mnt/hdd/mynode/thunderhub

sync
sleep 3s