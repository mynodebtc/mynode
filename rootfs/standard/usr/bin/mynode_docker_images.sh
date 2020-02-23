#!/bin/bash

set -e
set -x 

source /usr/share/mynode/mynode_config.sh

echo "Starting mynode_docker_images.sh ..."

# Drive should be mounted, let's still wait a bit
sleep 60s

echo "Waiting on bitcoin to sync so drive usage is lower..."
/usr/bin/wait_on_bitcoin.sh

while true; do
    echo "Checking for building new docker images..."
    touch /tmp/installing_docker_images

    # Pull images that don't need to be built
    docker pull netdata/netdata

    # Upgrade WebSSH2
    echo "Checking for new webssh2..."
    WEBSSH2_UPGRADE_URL=https://github.com/billchurch/webssh2/archive/v0.2.10-0.tar.gz
    WEBSSH2_UPGRADE_URL_FILE=/mnt/hdd/mynode/settings/webssh2_url
    CURRENT=""
    if [ -f $WEBSSH2_UPGRADE_URL_FILE ]; then
        CURRENT=$(cat $WEBSSH2_UPGRADE_URL_FILE)
    fi
    if [ "$CURRENT" != "$WEBSSH2_UPGRADE_URL" ]; then
        docker rmi webssh2 || true

        cd /tmp/
        rm -rf webssh2
        wget $WEBSSH2_UPGRADE_URL -O webssh2.tar.gz
        tar -xvf webssh2.tar.gz
        rm webssh2.tar.gz
        mv webssh2-* webssh2
        cd webssh2
        docker build -t webssh2 .

        echo $WEBSSH2_UPGRADE_URL > $WEBSSH2_UPGRADE_URL_FILE
    fi

    # Upgrade mempool.space
    echo "Checking for new mempool.space..."
    MEMPOOLSPACE_UPGRADE_URL=https://github.com/mempool-space/mempool.space/archive/8835c399e9b00c2579ed0bbd72f8cca4c5823dad.zip
    MEMPOOLSPACE_UPGRADE_URL_FILE=/mnt/hdd/mynode/settings/mempoolspace_url
    CURRENT=""
    if [ -f $MEMPOOLSPACE_UPGRADE_URL_FILE ]; then
        CURRENT=$(cat $MEMPOOLSPACE_UPGRADE_URL_FILE)
    fi
    if [ "$CURRENT" != "$MEMPOOLSPACE_UPGRADE_URL" ]; then
        docker rmi mempoolspace || true

        cd /opt/mynode
        rm -rf mempoolspace
        wget $MEMPOOLSPACE_UPGRADE_URL -O mempool.zip
        unzip -o mempool.zip
        rm mempool.zip
        mv mempool* mempoolspace
        cd mempoolspace
        sync
        sleep 3s
        docker build -t mempoolspace .

        echo $MEMPOOLSPACE_UPGRADE_URL > $MEMPOOLSPACE_UPGRADE_URL_FILE
    fi

    rm -f /tmp/installing_docker_images

    # Wait a day
    sleep 1d
done

# We should not exit
exit 1
