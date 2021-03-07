#!/bin/bash

source /usr/share/mynode/mynode_config.sh

mkdir -p $LND_BACKUP_FOLDER

echo "Waiting on lnd channel backup..."
while [ ! -f $LND_CHANNEL_FILE ]; do
    sleep 1m
done
echo "Channel backup found!"

# Always copy once to make first backup
cp -f $LND_CHANNEL_FILE $LND_CHANNEL_FILE_BACKUP

while true; do
    # If file has been deleted, exit so we cat restart
    if [ ! -f $LND_CHANNEL_FILE ]; then
        echo "Channel file deleted... exiting."
        exit 1
    fi

    # Wait for changes
    inotifywait -e modify -e create -e delete $LND_CHANNEL_FILE
    cp -f $LND_CHANNEL_FILE $LND_CHANNEL_FILE_BACKUP
    echo "Backed up LND channels!"
done

# Should never exit
exit 99