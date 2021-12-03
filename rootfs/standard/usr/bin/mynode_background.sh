#!/bin/bash

set -e
set -x 

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_app_versions.sh

# NOTE: Background services will run before mynode service completes, so a drive MAY NOT be attached

COUNTER=0
BITCOIN_SYNCED=0

while true; do

    # Check for under voltage, throttling, etc... every 2 min on Raspis
    if [ $(( $COUNTER % 2 )) -eq 0 ]; then
        if [ $IS_RASPI -eq 1 ]; then
            STATUS=$(vcgencmd get_throttled)
            STATUS=${STATUS#*=}
            echo $STATUS > /tmp/get_throttled_data
        fi
    fi

    # Download bitcoin whitepaper
    if [ -f "/mnt/hdd/mynode/.mynode_bitcoin_synced" ]; then
        if [ ! -f /mnt/hdd/mynode/bitcoin/bitcoin_whitepaper.pdf ]; then
            sudo -u bitcoin bitcoin-cli getrawtransaction 54e48e5f5c656b26c3bca14a8c95aa583d07ebe84dde3b7dd4a78f4e4186e713 true | \
                jq -r '.vout[].scriptPubKey.asm' | cut -c3- | \
                xxd -p -r | tail +9c | head -c 184292 > /mnt/hdd/mynode/bitcoin/bitcoin_whitepaper.pdf || \
                rm -f /mnt/hdd/mynode/bitcoin/bitcoin_whitepaper.pdf || true
        fi
    fi

    # Custom startup hook - post-bitcoin-synced
    if [ -f /usr/local/bin/mynode_hook_post_bitcoin_synced.sh ]; then
        if [ $BITCOIN_SYNCED == 0 ] && [ -f $BITCOIN_SYNCED_FILE ]; then
            /bin/bash /usr/local/bin/mynode_hook_post_bitcoin_synced.sh || true
            BITCOIN_SYNCED=1
        else
            BITCOIN_SYNCED=0
        fi
    fi


    # Increment counter and sleep 1 min
    COUNTER=$((COUNTER+1))
    sleep 1m
done
