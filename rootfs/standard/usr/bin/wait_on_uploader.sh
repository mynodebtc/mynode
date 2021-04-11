#!/bin/bash

set -e
set -x

source /usr/share/mynode/mynode_config.sh

# Don't start bitcoin if we are marked as an uploader
echo "Checking if uploader..."
while [ -f $UPLOADER_FILE ]; do
    echo "We are an uploader, sleeping for 15 minutes..."
    /bin/sleep 15m
done

exit 0