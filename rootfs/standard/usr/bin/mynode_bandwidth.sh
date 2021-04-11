#!/bin/bash

set -e
set -x

source /usr/share/mynode/mynode_config.sh

if [ ! -f $QUICKSYNC_UPLOAD_RATE_FILE ]; then
    UPLOAD_RATE=1000
    if [ $IS_RASPI3 -eq 1 ]; then
        UPLOAD_RATE=0
    fi
    echo "$UPLOAD_RATE" > $QUICKSYNC_UPLOAD_RATE_FILE
else
    UPLOAD_RATE=$(cat $QUICKSYNC_UPLOAD_RATE_FILE)
fi

if [ ! -f $QUICKSYNC_BACKGROUND_DOWNLOAD_RATE_FILE ]; then
    DOWNLOAD_RATE=1000
    if [ $IS_RASPI3 -eq 1 ]; then
        DOWNLOAD_RATE=500
    fi
    echo "$DOWNLOAD_RATE" > $QUICKSYNC_BACKGROUND_DOWNLOAD_RATE_FILE
else
    DOWNLOAD_RATE=$(cat $QUICKSYNC_BACKGROUND_DOWNLOAD_RATE_FILE)
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
        transmission-remote -t 1 --peers 5
    elif [ ! -f "/mnt/hdd/mynode/quicksync/.quicksync_complete" ]; then
        echo "QuickSync not complete, limited upload, unlimited download"
        transmission-remote -u $UPLOAD_RATE
        transmission-remote -D
        transmission-remote -t 1 --peers 10
    elif [ ! -f "/mnt/hdd/mynode/.mynode_bitcoin_synced" ]; then
        echo "Bitcoin not synced, stopping upload, stopping download"
        transmission-remote -u 0
        transmission-remote -d 0
    elif [[ "$PERCENT" != *"100"* ]]; then
        echo "QuickSync is downloading (but has completed once), limited upload, limited download"
        transmission-remote -u $UPLOAD_RATE
        transmission-remote -d $DOWNLOAD_RATE
    else
        echo "Setting upload rate for stable state"
        transmission-remote -u $UPLOAD_RATE
        transmission-remote -d $DOWNLOAD_RATE
        transmission-remote -t 1 --peers 5
    fi
    sleep 10m
done

# We should not exit
exit 1