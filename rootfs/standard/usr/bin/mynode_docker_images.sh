#!/bin/bash

set -e
set -x

source /usr/share/mynode/mynode_config.sh

echo "Starting mynode_docker_images.sh ..."
touch /tmp/installing_docker_images

# Drive should be mounted, let's still wait a bit
sleep 10s

echo "Waiting on bitcoin to sync so drive usage is lower..."
/usr/bin/wait_on_bitcoin.sh

while true; do
    echo "Checking for building new docker images..."
    touch /tmp/installing_docker_images

    # Pull images that don't need to be built
    # ???

    # Upgrade WebSSH2
    echo "Checking for new webssh2..."
    WEBSSH2_UPGRADE_VERSION=v0.2.10-0
    WEBSSH2_UPGRADE_URL=https://github.com/billchurch/webssh2/archive/${WEBSSH2_UPGRADE_VERSION}.tar.gz
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

    # Upgrade mempool
    echo "Checking for new mempool..."
    MEMPOOLSPACE_UPGRADE_VERSION=8835c399e9b00c2579ed0bbd72f8cca4c5823dad
    MEMPOOLSPACE_UPGRADE_URL=https://github.com/mempool-space/mempool.space/archive/${MEMPOOLSPACE_UPGRADE_VERSION}.zip
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

    # Install Dojo
    DOJO_VERSION="v1.8.0"
    DOJO_TAR_HASH="4c1e41790b6839f26ec947e96b3dc4c94e0218f0003e292a2c3808b0a1182fe6"
    DOJO_UPGRADE_URL=https://code.samourai.io/dojo/samourai-dojo/-/archive/$DOJO_VERSION/samourai-dojo-$DOJO_VERSION.tar.gz
    DOJO_UPGRADE_URL_FILE=/mnt/hdd/mynode/settings/dojo_url
    CURRENT=""
    INSTALL=true
    # If Upgrade file existed, mark "install" choice for legacy devices
    if [ -f $DOJO_UPGRADE_URL_FILE ]; then
        touch /mnt/hdd/mynode/settings/mynode_dojo_install
        sync
        sleep 3s
    fi
    # Only install Dojo if marked for installation
    if [ -f /mnt/hdd/mynode/settings/mynode_dojo_install ]; then
        if [ -f $DOJO_UPGRADE_URL_FILE ]; then
            INSTALL=false
            CURRENT=$(cat $DOJO_UPGRADE_URL_FILE)
        fi
        if [ "$CURRENT" != "$DOJO_UPGRADE_URL" ]; then
            sudo mkdir -p /opt/mynode/.dojo
            sudo mkdir -p /opt/mynode/dojo
            sudo rm -rf /opt/mynode/.dojo/*
            cd /opt/mynode/.dojo
            sudo wget -O dojo.tar.gz $DOJO_UPGRADE_URL

            # verify tar file
            echo "$DOJO_TAR_HASH  dojo.tar.gz" > /tmp/dojo_hash
            sha256sum --check /tmp/dojo_hash

            sudo tar -zxvf dojo.tar.gz
            sudo cp -r samourai-dojo*/* /opt/mynode/dojo
            cd /usr/bin
            sudo rm -rf /opt/mynode/.dojo/*

            # Configure Dojo for MyNode
            sudo ./mynode_gen_dojo_config.sh

            # Run Dojo Install or Upgrade
            cd /opt/mynode/dojo/docker/my-dojo
            INSTALL_PID=0
            if [ "$INSTALL" = "true" ]; then
                yes | sudo ./dojo.sh install &
                INSTALL_PID=$!
            else
                yes | sudo ./dojo.sh upgrade &
                INSTALL_PID=$!
            fi

            #Check for install/upgrade to finish to initialize Dojo mysql db
            cd /usr/bin
            sudo ./mynode_post_dojo.sh

            # Wait for install script to finish
            wait $INSTALL_PID

            # Try and start dojo (if upgraded and already enabled)
            systemctl restart dojo || true

            echo $DOJO_UPGRADE_URL > $DOJO_UPGRADE_URL_FILE
        fi
    fi

    rm -f /tmp/installing_docker_images

    # Wait a day
    sleep 1d
done

# We should not exit
exit 1
