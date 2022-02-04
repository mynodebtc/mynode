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
if [ -f /mnt/hdd/mynode/lnd/logs/bitcoin/mainnet/lnd.log ]; then
    cp /mnt/hdd/mynode/lnd/logs/bitcoin/mainnet/lnd.log /tmp/mynode_info/lnd_debug.log
fi
echo "" > /tmp/mynode_info/device_info

echo "##### df -h #####" >> /tmp/mynode_info/device_info
df -h >> /tmp/mynode_info/device_info
echo "" >> /tmp/mynode_info/device_info

echo "##### mount #####" >> /tmp/mynode_info/device_info
mount >> /tmp/mynode_info/device_info
echo "" >> /tmp/mynode_info/device_info

echo "##### docker ps #####" >> /tmp/mynode_info/device_info
if grep -qs '/mnt/hdd' /proc/mounts; then
    docker ps >> /tmp/mynode_info/device_info
else
    echo "Drive not mounted - skipping 'docker ps'" >> /tmp/mynode_info/device_info
fi
echo "" >> /tmp/mynode_info/device_info

# Create tarball
tar -czvf /tmp/mynode_logs.tar.gz /var/log/ /tmp/mynode_info/