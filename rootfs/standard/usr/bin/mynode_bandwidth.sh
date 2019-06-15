#!/bin/bash

set -e
set -x

source /usr/share/mynode/mynode_config.sh

# Let transmission startup
sleep 60s

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
    if [ -f $QUICKSYNC_BANDWIDTH_FILE ]; then
        RATE=$(cat $QUICKSYNC_BANDWIDTH_FILE)
        echo "Setting upload rate to $RATE kbps"
        transmission-remote -u $RATE
    else
        echo "Setting upload rate to unlimited"
        transmission-remote -U
    fi
    sleep 1d
done

# We should not exit
exit 1