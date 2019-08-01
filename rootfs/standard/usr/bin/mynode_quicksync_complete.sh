#!/bin/bash

set -e

source /usr/share/mynode/mynode_config.sh

if [ -f $QUICKSYNC_DIR/.quicksync_complete ] && [ -f $QUICKSYNC_DIR/.quicksync_download_complete ]; then
    echo "Exiting quicksync_complete. Quicksync already completed. This was just a re-download."
    exit 0
fi

# Mark download complete
touch $QUICKSYNC_DIR/.quicksync_download_complete
sync

# Copy files
echo "quicksync_copy" > $MYNODE_DIR/.mynode_status
rm -rf $MYNODE_DIR/bitcoin/blocks/
rm -rf $MYNODE_DIR/bitcoin/chainstate/
tar -xvf $QUICKSYNC_DIR/blockchain*.tar.gz -C $MYNODE_DIR/bitcoin/ --dereference

# Mark quicksync complete and give BTC a few minutes to startup with its new data
touch $QUICKSYNC_DIR/.quicksync_complete
sync
sleep 5m
echo "stable" > $MYNODE_DIR/.mynode_status
sync

exit 0