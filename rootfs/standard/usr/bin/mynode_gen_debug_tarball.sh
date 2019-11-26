#!/bin/bash

set -x

# Clean space for tarball + setup
rm -rf /tmp/mynode_logs.tar.gz
rm -rf /tmp/mynode_info/
mkdir -p /tmp/mynode_info/

# Save helpful info
mynode-get-quicksync-status > /tmp/mynode_info/quicksync_state.txt
cp /usr/share/mynode/version /tmp/mynode_info/version
cp -rf /home/admin/upgrade_logs /tmp/mynode_info/
cp /mnt/hdd/mynode/bitcoin/debug.log /tmp/mynode_info/bitcoin_debug.log

echo "" > /tmp/mynode_info/device_info
echo "##### df -h #####" >> /tmp/mynode_info/device_info
df -h >> /tmp/mynode_info/device_info
echo "" >> /tmp/mynode_info/device_info
echo "##### mount #####" >> /tmp/mynode_info/device_info
mount >> /tmp/mynode_info/device_info
echo "" >> /tmp/mynode_info/device_info
echo "##### docker ps #####" >> /tmp/mynode_info/device_info
docker ps >> /tmp/mynode_info/device_info

# Create tarball
tar -czvf /tmp/mynode_logs.tar.gz /var/log/ /tmp/mynode_info/