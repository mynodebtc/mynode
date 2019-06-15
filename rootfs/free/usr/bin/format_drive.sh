#!/bin/bash
dev=$1

# Delete any old partitions
for i in `seq 4 1`;
do
    sudo parted --script /dev/$dev rm $i || true
done

# Try to setup new table
parted --script /dev/$dev mklabel gpt || true

# Make new partition with entire drive
parted --script /dev/$dev mkpart primary ext4 0% 100%

partprobe /dev/$dev
sleep 2