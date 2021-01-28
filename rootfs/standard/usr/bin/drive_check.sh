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

    # Check drive usage
    usage=$(df -h /mnt/hdd | grep /dev | awk '{print $5}' | cut -d'%' -f1)
    echo "Usage $usage"
    if [ $usage -ge 99 ]; then
        # Usage is 99%+, reboot to get into drive_full state with services stopped
        /usr/bin/mynode-reboot
    fi

    # Wait, check again in one minute
    sleep 60
    lsblk $drive &> /dev/null
done

echo "Drive $drive NOT found! Rebooting."
reboot -f