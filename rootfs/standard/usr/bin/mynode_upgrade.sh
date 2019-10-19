#!/bin/bash

set -x
#set -e

source /usr/share/mynode/mynode_config.sh

# Setup
rm -rf /tmp/mynode_release_latest.tar.gz
rm -rf /tmp/mynode_release.pub
rm -rf /tmp/upgrade/
mkdir -p /tmp/upgrade/

# Download Latest
wget $UPGRADE_DOWNLOAD_URL -O /tmp/mynode_release_latest.tar.gz
wget $UPGRADE_DOWNLOAD_SIGNATURE_URL -O /tmp/mynode_release_latest.sha256
wget $UPGRADE_PUBKEY_URL -O /tmp/mynode_release.pub

openssl dgst -sha256 -verify /tmp/mynode_release.pub -signature /tmp/mynode_release_latest.sha256 /tmp/mynode_release_latest.tar.gz
if [ $? -ne 0 ]; then
    echo "UPGRADE FAILED! Hash did not match!" >> /var/log/upgrade.log
    exit 1
fi

# Extract to temp location
tar -xvf /tmp/mynode_release_latest.tar.gz -C /tmp/upgrade/

# Install files
if [ $IS_X86 = 1 ]; then
    rsync -r -K /tmp/upgrade/out/rootfs_${DEVICE_TYPE}/* /
else
    cp -rf /tmp/upgrade/out/rootfs_${DEVICE_TYPE}/* /
fi
sleep 1
sync
sleep 1

# Run post upgrade script
/bin/bash /usr/bin/mynode_post_upgrade.sh > /home/admin/upgrade_log.txt