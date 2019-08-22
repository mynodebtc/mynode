#!/bin/bash

set -e
set -x

source /usr/share/mynode/mynode_config.sh

BACKGROUND_DL_RATE=2500
if [ $IS_RASPI3 -eq 1 ]; then
    BACKGROUND_DL_RATE=500
fi

# Let transmission startup
sleep 60s

# Check transmission is started
until transmission-remote -l ; do
    sleep 60s
done

# Default is download only until we determine state
transmission-remote -u 0
transmission-remote -D

# Determine current state
while true; do
    PERCENT=$(transmission-remote -t 1 -i | grep "Percent Done:")
    if [ -f $UPLOADER_FILE ]; then
        echo "Marked as uploader, unlimited upload, unlimited download"
        transmission-remote -U
        transmission-remote -D
    elif [ ! -f "/mnt/hdd/mynode/quicksync/.quicksync_complete" ]; then
        echo "QuickSync not complete, stopping upload, unlimited download"
        transmission-remote -u 0
        transmission-remote -D
    elif [ ! -f "/mnt/hdd/mynode/.mynode_bitcoind_synced" ]; then
        echo "Bitcoin not synced, stopping upload, stopping download"
        transmission-remote -u 0
        transmission-remote -d 0
    elif [[ "$PERCENT" != *"100"* ]]; then
        echo "QuickSync is downloading (but has completed once), stopping upload, limited download"
        transmission-remote -u 0
        transmission-remote -d $BACKGROUND_DL_RATE
    elif [ -f $QUICKSYNC_BANDWIDTH_FILE ]; then
        RATE=$(cat $QUICKSYNC_BANDWIDTH_FILE)
        echo "Setting upload rate to $RATE kbps"
        transmission-remote -u $RATE
        transmission-remote -d $BACKGROUND_DL_RATE
    else
        echo "Setting upload rate to unlimited"
        transmission-remote -U
        transmission-remote -D
    fi
    sleep 10m
done

# We should not exit
exit 1