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
tar -xvf $QUICKSYNC_DIR/blockchain*.tar.gz -C $MYNODE_DIR/bitcoin/ --dereference

# Mark quicksync complete
echo "stable" > $MYNODE_DIR/.mynode_status
touch $QUICKSYNC_DIR/.quicksync_complete
sync

exit 0