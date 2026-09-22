#!/bin/bash

# set -e # Stop on error (skip for now with new logic to allow an attempt to install each container)
set -x

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_functions.sh
source /usr/share/mynode/mynode_app_versions.sh

echo "Starting mynode_docker_images.sh ..."
touch /tmp/installing_docker_images

# Wait for name resolution before downloading anything. This can run seconds after boot, before
# DNS is usable, and a download that fails then is not retried until the next pass.
wait_on_dns() {
    for _ in $(seq 1 60); do
        if getent hosts github.com > /dev/null 2>&1 ; then
            return 0
        fi
        echo "Waiting on DNS..."
        sleep 5s
    done
    echo "WARNING: DNS is still not working, downloads will likely fail"
    return 1
}

# Drive should be mounted, let's still wait a bit
sleep 10s

echo "Waiting on bitcoin to sync so drive usage is lower..."
/usr/bin/wait_on_bitcoin.sh

while true; do
    echo "Checking for building new docker images..."
    touch /tmp/installing_docker_images

    # Set to 1 by any install that failed for a reason worth retrying soon, rather than waiting
    # a full day with the app enabled and not installed
    INSTALL_FAILED=0

    wait_on_dns || INSTALL_FAILED=1

    # Check if we happened to change architectures (move from 32-bit to 64-bit Raspi4 image)
    CURRENT_ARCH=$(uname -m)
    SAVED_ARCH="unknown"
    if [ ! -f $DEVICE_ARCHITECTURE_FILE ]; then
        echo $CURRENT_ARCH > $DEVICE_ARCHITECTURE_FILE
    fi
    if [ -f $DEVICE_ARCHITECTURE_FILE ]; then
        SAVED_ARCH=$(cat $DEVICE_ARCHITECTURE_FILE)
    fi
    if [ "$CURRENT_ARCH" != "$SAVED_ARCH" ]; then
        # Reset docker stuff
        docker system prune --all --force

        # Remove containers known to cause problems if cached
        remove_docker_images_by_name 'debian:buster-slim'

        # Mark mempool and dojo for re-install
        #  Must reset version for Dojo or it will fully re-install and break rather than 'upgrade'
        echo "reset" > $WEBSSH2_VERSION_FILE
        echo "reset" > $NETDATA_VERSION_FILE
        echo "reset" > $MEMPOOL_VERSION_FILE
        echo "reset" > $DOJO_VERSION_FILE
    fi
    echo $CURRENT_ARCH > $DEVICE_ARCHITECTURE_FILE

    # Pull images that don't need to be built
    # ???

    # Upgrade Netdata
    echo "Checking for new netdata..."
    enabled=$(systemctl is-enabled netdata)
    if [ "$enabled" = "enabled" ]; then
        touch /mnt/hdd/mynode/settings/install_netdata
        sync
    fi
    if should_install_app "netdata" ; then
        CURRENT=""
        if [ -f $NETDATA_VERSION_FILE ]; then
            CURRENT=$(cat $NETDATA_VERSION_FILE)
        fi
        if [ "$CURRENT" != "$NETDATA_VERSION" ]; then
            remove_docker_images_by_name 'netdata'

            if pull_app_docker_image netdata/netdata "$NETDATA_VERSION" netdata "$NETDATA_DIGEST"; then
                echo $NETDATA_VERSION > $NETDATA_VERSION_FILE
            fi
        fi
        touch /tmp/need_application_refresh
    fi
    

    # Upgrade WebSSH2
    echo "Checking for new webssh2..."
    WEBSSH2_UPGRADE_URL=https://github.com/billchurch/webssh2/archive/${WEBSSH2_VERSION}.tar.gz
    CURRENT=""
    if [ -f $WEBSSH2_VERSION_FILE ]; then
        CURRENT=$(cat $WEBSSH2_VERSION_FILE)
    fi
    if [ "$CURRENT" != "$WEBSSH2_VERSION" ]; then
        remove_docker_images_by_name 'webssh2'

        cd /tmp/
        rm -rf webssh2
        wget $WEBSSH2_UPGRADE_URL -O webssh2.tar.gz
        if check_app_download webssh2.tar.gz webssh2 "$WEBSSH2_VERSION" "$WEBSSH2_SHA256"; then
            tar -xvf webssh2.tar.gz
            rm webssh2.tar.gz
            mv webssh2-* webssh2
            cd webssh2
            docker build -t webssh2 .
            if [ $? == 0 ]; then
                echo $WEBSSH2_VERSION > $WEBSSH2_VERSION_FILE
            fi
        fi
    fi
    touch /tmp/need_application_refresh


    # Upgrade mempool
    MEMPOOL_UPGRADE_URL=https://github.com/mempool/mempool/archive/${MEMPOOL_VERSION}.tar.gz
    echo "Checking for new mempool..."
    if should_install_app "mempool" ; then
        CURRENT=""
        if [ -f $MEMPOOL_VERSION_FILE ]; then
            CURRENT=$(cat $MEMPOOL_VERSION_FILE)
        fi
        if [ "$CURRENT" != "$MEMPOOL_VERSION" ]; then
            remove_docker_images_by_name 'mempoolspace' # Remove old v1 image
            remove_docker_images_by_name 'mempool'      # Remove v2 images

            cd /mnt/hdd/mynode/mempool
            rm -rf data
            rm -rf mysql
            mkdir -p data mysql/data

            rm -rf /opt/download/mempool
            mkdir -p /opt/download/mempool
            cd /opt/download/mempool
            wget $MEMPOOL_UPGRADE_URL -O mempool.tar.gz
            tar -xvf mempool.tar.gz
            rm mempool.tar.gz
            mv mempool-* mempool

            MEMPOOL_PULLED=1
            pull_app_docker_image mempool/frontend "$MEMPOOL_VERSION" mempool "$MEMPOOL_FRONTEND_DIGEST" || MEMPOOL_PULLED=0
            pull_app_docker_image mempool/backend "$MEMPOOL_VERSION" mempool "$MEMPOOL_BACKEND_DIGEST" || MEMPOOL_PULLED=0
            if [ $IS_RASPI -eq 0 ] || [ $IS_ARM64 -eq 1 ]; then
                pull_app_docker_image mariadb 10.9.3 mariadb "$MARIADB_DIGEST" || MEMPOOL_PULLED=0
            fi

            if [ $MEMPOOL_PULLED = 1 ]; then
                enabled=$(systemctl is-enabled mempool)
                if [ "$enabled" = "enabled" ]; then
                    systemctl restart mempool &
                fi

                echo $MEMPOOL_VERSION > $MEMPOOL_VERSION_FILE
            fi
        fi
    fi
    touch /tmp/need_application_refresh


    # Upgrade BTCPay Server
    if should_install_app "btcpayserver" ; then
        CURRENT=""
        if [ -f $BTCPAYSERVER_VERSION_FILE ]; then
            CURRENT=$(cat $BTCPAYSERVER_VERSION_FILE)
        fi
        if [ "$CURRENT" != "$BTCPAYSERVER_VERSION" ]; then
            # Create a folder for BTCPay
            rm -rf /mnt/hdd/mynode/btcpayserver
            mkdir -p /mnt/hdd/mynode/btcpayserver
            cd /mnt/hdd/mynode/btcpayserver

            # Clone this repository. A failure here leaves btcpayserver enabled with an empty
            # folder, so mark the pass failed and let the loop come back to it.
            CLONED=1
            git clone https://github.com/btcpayserver/btcpayserver-docker || CLONED=0
            if [ $CLONED = 0 ]; then
                INSTALL_FAILED=1
            fi

            if [ $CLONED = 1 ] && cd btcpayserver-docker && git -c advice.detachedHead=false checkout "$BTCPAYSERVER_DOCKER_COMMIT"; then
                # Run btcpay-setup.sh with the right parameters
                export BTCPAY_HOST="mynode.local"
                export NBITCOIN_NETWORK="mainnet"
                export BTCPAYGEN_CRYPTO1="btc"
                export BTCPAYGEN_ADDITIONAL_FRAGMENTS="btcpayserver-noreverseproxy;bitcoin.custom;lnd.custom;nbxplorer"
                export BTCPAYGEN_EXCLUDE_FRAGMENTS="opt-add-tor;bitcoin;bitcoin-lnd;"
                export BTCPAYGEN_REVERSEPROXY="none"
                export NOREVERSEPROXY_HTTP_PORT=49392
                export REVERSEPROXY_HTTP_PORT=49392
                export REMOTE_BTC_RPC_USERNAME="mynode"
                BTCRPCPW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
                export REMOTE_BTC_RPC_PASSWORD="$BTCRPCPW"
                export BTCPAYGEN_LIGHTNING="lnd"
                export BTCPAY_ENABLE_SSH=false
                export BTCPAY_IMAGE=btcpayserver/btcpayserver:$BTCPAYSERVER_VERSION

                cp -f /usr/share/btcpayserver/bitcoin.custom.yml /mnt/hdd/mynode/btcpayserver/btcpayserver-docker/docker-compose-generator/docker-fragments/bitcoin.custom.yml
                cp -f /usr/share/btcpayserver/lnd.custom.yml /mnt/hdd/mynode/btcpayserver/btcpayserver-docker/docker-compose-generator/docker-fragments/lnd.custom.yml

                rm -rf /usr/local/bin/btcpay-*
                rm -rf /usr/local/bin/changedomain.sh

                #. ./btcpay-setup.sh # Install and run
                bash -c ". ./btcpay-setup.sh --install-only --no-startup-register --no-systemd-reload"

                # Update NBXplorer variables (needed to pull containers)
                NBXPLORER_VARIABLES_FILE=/mnt/hdd/mynode/btcpayserver/btcpayserver-docker/Generated/nbxplorer-variables.env
                echo "NBXPLORER_BTCRPCUSER=mynode"            > $NBXPLORER_VARIABLES_FILE
                echo "NBXPLORER_BTCRPCPASSWORD=$BTCRPCPW"    >> $NBXPLORER_VARIABLES_FILE

                # Pull latest containers
                /bin/bash -c  '. "/etc/profile.d/btcpay-env.sh" && cd "$BTCPAY_BASE_DIRECTORY/btcpayserver-docker" && . helpers.sh && btcpay_pull'

                echo $BTCPAYSERVER_VERSION > $BTCPAYSERVER_VERSION_FILE
            fi
        fi
    else
        # BTC Pay Not Installed, make sure old images are gone to prevent docker compose from running
        # For some reason, containers will re-launch after uninstalling btcpayserver
        echo "Removing BTC Pay Containers..."
        docker kill $(docker ps -a -q --filter name=generated_postgres) 2>/dev/null || true
        docker kill $(docker ps -a -q --filter name=generated_btcpayserver) 2>/dev/null || true
        docker kill $(docker ps -a -q --filter name=generated_nbxplorer) 2>/dev/null || true
        docker rm $(docker ps -a -q --filter name=generated_postgres) 2>/dev/null || true
        docker rm $(docker ps -a -q --filter name=generated_btcpayserver) 2>/dev/null || true
        docker rm $(docker ps -a -q --filter name=generated_nbxplorer) 2>/dev/null || true
        remove_docker_images_by_name 'btcpayserver/btcpayserver'
        remove_docker_images_by_name 'nicolasdorier/nbxplorer'
        remove_docker_images_by_name 'btcpayserver/postgres'
    fi
    touch /tmp/need_application_refresh


    # Upgrade LNbits
    if should_install_app "lnbits" ; then
        CURRENT=""
        if [ -f $LNBITS_VERSION_FILE ]; then
            CURRENT=$(cat $LNBITS_VERSION_FILE)
        fi
        if [ "$CURRENT" != "$LNBITS_VERSION" ]; then
            remove_docker_images_by_name 'lnbits'

            if [ ! -d "/opt/mynode/lnbits" ]; then
                mkdir -p "/opt/mynode/lnbits"
            fi

            # Copy over config file
            # Handled in pre_lnbits.sh

            # Pull lnbits docker container
            if pull_app_docker_image lnbits/lnbits "$LNBITS_VERSION" lnbits "$LNBITS_DIGEST"; then
                docker tag lnbits/lnbits:$LNBITS_VERSION lnbits
                echo $LNBITS_VERSION > $LNBITS_VERSION_FILE
            fi
        fi
    fi
    touch /tmp/need_application_refresh

    rm -f /tmp/installing_docker_images
    touch /tmp/installing_docker_images_completed_once

    if [ $INSTALL_FAILED = 1 ]; then
        # Something transient - come back in five minutes instead of a day
        echo "An install did not complete, retrying shortly..."
        sleep 5m
    else
        # Wait a day
        sleep 1d
    fi
done

# We should not exit
exit 1
