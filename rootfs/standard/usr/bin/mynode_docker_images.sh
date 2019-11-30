#!/bin/bash

set -e
set -x 

source /usr/share/mynode/mynode_config.sh

# Drive should be mounted, let's still wait a bit
sleep 60s

# Loop and check every 1 day
while [ 1 ]; do

    # Upgrade WebSSH2
    WEBSSH2_UPGRADE_URL=https://github.com/billchurch/webssh2/archive/v0.2.10-0.tar.gz
    WEBSSH2_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.webssh2_url
    CURRENT=""
    if [ -f $WEBSSH2_UPGRADE_URL_FILE ]; then
        CURRENT=$(cat $WEBSSH2_UPGRADE_URL_FILE)
    fi
    if [ "$CURRENT" != "$WEBSSH2_UPGRADE_URL" ]; then
        cd /opt/mynode
        rm -rf webssh2
        wget $WEBSSH2_UPGRADE_URL -O webssh2.tar.gz
        tar -xvf webssh2.tar.gz
        rm webssh2.tar.gz
        mv webssh2-* webssh2
        cd webssh2
        mv app/config.json.sample app/config.json
        docker build -t webssh2 .

        echo $WEBSSH2_UPGRADE_URL > $WEBSSH2_UPGRADE_URL_FILE
    fi

    # Check again in a day
    sleep 24h
done
