#!/bin/bash

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x

BTCRPCPW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)

cp -f /usr/share/mynode/mempool-docker-compose.yml /mnt/hdd/mynode/mempool/docker-compose.yml

cp -f /usr/share/mynode/mempool.env /mnt/hdd/mynode/mempool/.env
sed -i "s/VERSION=.*/VERSION=$MEMPOOL_VERSION/g" /mnt/hdd/mynode/mempool/.env
sed -i "s/BITCOIN_RPC_PASS=.*/BITCOIN_RPC_PASS=$BTCRPCPW/g" /mnt/hdd/mynode/mempool/.env

if [ $IS_RASPI -eq 1 ] && [ $IS_ARM64 -eq 0 ]; then
    sed -i "s|MARIA_DB_IMAGE=.*|MARIA_DB_IMAGE=hypriot/rpi-mysql:latest|g" /mnt/hdd/mynode/mempool/.env
else
    sed -i "s|MARIA_DB_IMAGE=.*|MARIA_DB_IMAGE=mariadb:10.9.3|g" /mnt/hdd/mynode/mempool/.env
fi

chown -R mempool:mempool /mnt/hdd/mynode/mempool
