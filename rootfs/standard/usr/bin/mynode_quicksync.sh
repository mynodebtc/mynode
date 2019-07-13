#!/bin/bash

# mynode_quicksync.sh
# Downloads blockchain up through Feb 2019 for MUCH faster syncing
# Seeds afterwards if not disabled
# Dependencies: Must run after mynode script so HDD is mounted

set -e
set -x

source /usr/share/mynode/mynode_config.sh

mkdir -p $QUICKSYNC_DIR
mkdir -p $QUICKSYNC_CONFIG_DIR

cp -f /usr/share/quicksync/settings.json $QUICKSYNC_CONFIG_DIR/settings.json

# Make sure folder exists
mkdir -p $QUICKSYNC_DIR
if [ ! -f $QUICKSYNC_DIR/.quicksync_download_complete ]; then
    echo "quicksync_download" > $MYNODE_DIR/.mynode_status
fi
echo "Starting quicksync..."

# Download finished, but failed during copy, recopy
if [ ! -f $QUICKSYNC_DIR/.quicksync_complete ] && [ -f $QUICKSYNC_DIR/.quicksync_download_complete ]; then
    echo "Quicksync download complete, needs copy"
    /usr/bin/mynode_quicksync_complete.sh
fi
# Check if quicksync was completed
if [ -f $QUICKSYNC_DIR/.quicksync_complete ]; then
    echo "stable" > $MYNODE_DIR/.mynode_status
fi

# Download torrent
rm -rf $QUICKSYNC_DIR/blockchain_temp.torrent
wget -O $QUICKSYNC_DIR/blockchain_temp.torrent $QUICKSYNC_TORRENT_URL
sync
sleep 1

if [ ! -f $QUICKSYNC_DIR/blockchain_temp.torrent ]; then
    echo "Torrent download failed...."
    exit 1
fi

# Check if new torrent is updated
if [ ! -f $QUICKSYNC_DIR/blockchain.torrent ]; then
    cp $QUICKSYNC_DIR/blockchain_temp.torrent $QUICKSYNC_DIR/blockchain.torrent
else
    # Run commands as long as torrents are different (last command updates torrent file)
    COMPLETED=0
    if [ -f $QUICKSYNC_DIR/.quicksync_complete ]; then
        COMPLETED=1
    fi
    
    NEW_TORRENT=0
    cmp --silent $QUICKSYNC_DIR/blockchain_temp.torrent $QUICKSYNC_DIR/blockchain.torrent || NEW_TORRENT=1
    if [ $NEW_TORRENT -eq 1 ]; then
        # Delete old QuickSync data+config and start new one
        rm -f $QUICKSYNC_DIR/*
        rm -rf $QUICKSYNC_CONFIG_DIR
        mkdir -p $QUICKSYNC_CONFIG_DIR
        cp -f /usr/share/quicksync/settings.json $QUICKSYNC_CONFIG_DIR/settings.json
        cp $QUICKSYNC_DIR/blockchain_temp.torrent $QUICKSYNC_DIR/blockchain.torrent
        sync

        # If download had been completed
        if [ $COMPLETED -eq 1 ]; then
            touch $QUICKSYNC_DIR/.quicksync_download_complete
            touch $QUICKSYNC_DIR/.quicksync_complete

            # Since this will start/continue a background download, wait so everything else boots smoothly
            sleep 5m
            /usr/bin/wait_on_bitcoin.sh
            sleep 10m
        fi
        sync
    fi
fi

# Start torrent
echo "Running torrent..."
transmission-cli \
    --download-dir $QUICKSYNC_DIR \
    --config-dir $QUICKSYNC_CONFIG_DIR \
    --finish=/usr/bin/mynode_quicksync_complete.sh \
    $QUICKSYNC_DIR/blockchain.torrent
