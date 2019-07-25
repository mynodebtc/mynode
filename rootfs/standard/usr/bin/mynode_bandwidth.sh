#!/bin/bash

set -e
set -x

source /usr/share/mynode/mynode_config.sh

# Let transmission startup
sleep 60s

# If marked as uploader, dont slow down
while [ -f $UPLOADER_FILE ]; do
    echo "Marked as uploader, unlimited upload"
    transmission-remote -U
    sleep 1h
done

# Upload slowly while downloading
transmission-remote -u 0

# Wait until download is complete...
while [ ! -f "/mnt/hdd/mynode/quicksync/.quicksync_complete" ]; do
    sleep 30s
done

# Wait until blockchain is synced...
while [ ! -f "/mnt/hdd/mynode/.mynode_bitcoind_synced" ]; do
    sleep 30s
done

# Enable uploading
echo "QuickSync Complete! Enabling Uploading."

while true; do
    if [ -f $UPLOADER_FILE ]; then
        echo "Marked as uploader, unlimited upload"
        transmission-remote -U
    elif [ ! -f "/mnt/hdd/mynode/quicksync/.quicksync_complete" ]; then
        echo "QuickSync not complete, stopping upload"
        transmission-remote -u 0
    elif [ ! -f "/mnt/hdd/mynode/.mynode_bitcoind_synced" ]; then
        echo "Bitcoin not synced, stopping upload"
        transmission-remote -u 0
    elif [ -f $QUICKSYNC_BANDWIDTH_FILE ]; then
        RATE=$(cat $QUICKSYNC_BANDWIDTH_FILE)
        echo "Setting upload rate to $RATE kbps"
        transmission-remote -u $RATE
    else
        echo "Setting upload rate to unlimited"
        transmission-remote -U
    fi
    sleep 1h
done

# We should not exit
exit 1