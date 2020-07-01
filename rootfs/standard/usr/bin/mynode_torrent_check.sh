#!/bin/bash

source /usr/share/mynode/mynode_config.sh

sleep 1m

echo "Waiting until QuickSync is complete..."
while [ ! -f "$QUICKSYNC_COMPLETE_FILE" ]; do
    sleep 1h
done

# No need to check for new torrent right away
sleep 2m

while true; do
    # Wait a while... we don't want everyone starting on a new torrent at once
    if [ -f $UPLOADER_FILE ]; then
        echo "Marked as uploader, checking for new torrent..."

        # Download current torrent
        rm -rf /tmp/blockchain_temp.torrent
        if [ -f $UPLOADER_FILE ]; then
            torify wget -O /tmp/blockchain_temp.torrent $QUICKSYNC_TORRENT_BETA_URL
        else
            torify wget -O /tmp/blockchain_temp.torrent $QUICKSYNC_TORRENT_URL
        fi
        if [ -f /tmp/blockchain_temp.torrent ]; then
            NEW_TORRENT=0
            cmp --silent /tmp/blockchain_temp.torrent $QUICKSYNC_DIR/blockchain.torrent || NEW_TORRENT=1
            if [ $NEW_TORRENT -eq 1 ]; then
                # Reboot to restart and get new torrent
                sleep 30s
                reboot 
            else
                echo "Torrent has not changed."
            fi
        else
            echo "Torrent download failed...."
        fi
    fi

    sleep 1d
done

# Should never exit
exit 99