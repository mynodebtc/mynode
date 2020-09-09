#!/bin/bash

# Find 
drive=""

drive=$(cat /tmp/.mynode_drive)
while [ -z "$drive" ]; do
    sleep 10
    echo "Waiting on myNode Drive..."
    drive=$(cat /tmp/.mynode_drive)
done

echo "Found Drive: $drive"

lsblk $drive &> /dev/null
while [ $? -eq 0 ]; do
    #echo "$drive still found..."
    sleep 60
    lsblk $drive &> /dev/null
done

echo "Drive $drive NOT found! Rebooting."
reboot -f