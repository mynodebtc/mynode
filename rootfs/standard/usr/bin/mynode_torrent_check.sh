#!/bin/bash

source /usr/share/mynode/mynode_config.sh

echo "Waiting until QuickSync is complete..."
while [ ! -f "$QUICKSYNC_COMPLETE_FILE" ]; do
    sleep 1m
done
echo "Quicksync Complete! Waiting until Bitcoin Sync is complete..."
while [ ! -f "$BITCOIN_SYNCED_FILE" ]; do
    sleep 1m
done
echo "Bitcoin Sync Complete! Checking if there is a new torrent available..."
sleep 1d

while true; do
    # Wait a while... we don't want everyone starting on a new torrent at once
    sleep 7d

    # Download current torrent
    rm -rf /tmp/blockchain_temp.torrent
    wget -O /tmp/blockchain_temp.torrent $QUICKSYNC_TORRENT_URL
    if [ -f /tmp/blockchain_temp.torrent ]; then
        NEW_TORRENT=0
        cmp --silent /tmp/blockchain_temp.torrent $QUICKSYNC_DIR/blockchain.torrent || NEW_TORRENT=1
        if [ $NEW_TORRENT -eq 1 ]; then
            # Reboot to restart and get new torrent
            reboot
        else
            echo "Torrent has not changed."
        fi
    else
        echo "Torrent download failed...."
    fi
done

# Should never exit
exit 99