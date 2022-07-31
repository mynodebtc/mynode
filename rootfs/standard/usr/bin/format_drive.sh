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
if [ -f /tmp/format_filesystem_btrfs ]; then
    parted --script /dev/$dev mkpart primary btrfs 0% 100%
else
    parted --script /dev/$dev mkpart primary ext4 0% 100%
fi

partprobe /dev/$dev
sleep 2