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
    mb_available=$(df --block-size=M /mnt/hdd | grep /dev | awk '{print $4}' | cut -d'M' -f1)
    if [ $mb_available -le 1000 ]; then
        # Usage is 99%+, reboot to get into drive_full state with services stopped
        echo "High Drive Usage: $mb_available MB available"
        /usr/bin/mynode-reboot
    fi

    # Wait, check again in one minute
    sleep 60
    lsblk $drive &> /dev/null
done

echo "Drive $drive NOT found! Rebooting."
reboot -f