#!/bin/bash

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x

cp -f /usr/share/mynode/mempool-docker-compose.yml /mnt/hdd/mynode/mempool/docker-compose.yml

cp -f /usr/share/mynode/mempool.env /mnt/hdd/mynode/mempool/.env
sed -i "s/VERSION=.*/VERSION=$MEMPOOL_VERSION/g" /mnt/hdd/mynode/mempool/.env
set +x
BTCRPCPW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
printf 's/BITCOIN_RPC_PASS=.*/BITCOIN_RPC_PASS=%s/g\n' "$BTCRPCPW" | sed -i -f - /mnt/hdd/mynode/mempool/.env
set -x

if [ $IS_RASPI -eq 1 ] && [ $IS_ARM64 -eq 0 ]; then
    sed -i "s|MARIA_DB_IMAGE=.*|MARIA_DB_IMAGE=hypriot/rpi-mysql:latest|g" /mnt/hdd/mynode/mempool/.env
else
    sed -i "s|MARIA_DB_IMAGE=.*|MARIA_DB_IMAGE=mariadb:10.9.3|g" /mnt/hdd/mynode/mempool/.env
fi

# MariaDB's image sets the owner of its database folder when the container starts
find /mnt/hdd/mynode/mempool -path /mnt/hdd/mynode/mempool/mysql -prune -o -exec chown mempool:mempool {} +
chmod 600 /mnt/hdd/mynode/mempool/.env
