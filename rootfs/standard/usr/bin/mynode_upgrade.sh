#!/bin/bash

set -x
#set -e

source /usr/share/mynode/mynode_config.sh

BETA=0
while test $# -gt 0
do
    case "$1" in
        beta) echo "Installing a beta..."
            BETA=1
            ;;
        *) echo "Unknown Argument: $1"
            exit 1
            ;;
    esac
    shift
done

# Setup
rm -rf /opt/mynode_release_latest.tar.gz
rm -rf /opt/mynode_release.pub
rm -rf /opt/upgrade/
mkdir -p /opt/upgrade/
mkdir -p /home/admin/upgrade_logs/

# Download Latest
if [ $BETA = 0 ]; then
    torify wget $UPGRADE_DOWNLOAD_URL -O /opt/mynode_release_latest.tar.gz || \
           wget $UPGRADE_DOWNLOAD_URL -O /opt/mynode_release_latest.tar.gz
    torify wget $UPGRADE_DOWNLOAD_SIGNATURE_URL -O /opt/mynode_release_latest.sha256 || \
           wget $UPGRADE_DOWNLOAD_SIGNATURE_URL -O /opt/mynode_release_latest.sha256
else
    torify wget $UPGRADE_BETA_DOWNLOAD_URL -O /opt/mynode_release_latest.tar.gz || \
           wget $UPGRADE_BETA_DOWNLOAD_URL -O /opt/mynode_release_latest.tar.gz
    torify wget $UPGRADE_BETA_DOWNLOAD_SIGNATURE_URL -O /opt/mynode_release_latest.sha256 || \
           wget $UPGRADE_BETA_DOWNLOAD_SIGNATURE_URL -O /opt/mynode_release_latest.sha256
fi
torify wget $UPGRADE_PUBKEY_URL -O /opt/mynode_release.pub || \
       wget $UPGRADE_PUBKEY_URL -O /opt/mynode_release.pub

openssl dgst -sha256 -verify /opt/mynode_release.pub -signature /opt/mynode_release_latest.sha256 /opt/mynode_release_latest.tar.gz
if [ $? -ne 0 ]; then
    echo "UPGRADE FAILED! Hash did not match!" >> /var/log/upgrade.log
    exit 1
fi

# Clear beta install marking
rm -f /usr/share/mynode/beta_version

# Extract to temp location
tar -xf /opt/mynode_release_latest.tar.gz -C /opt/upgrade/

# Install files
VERSION=$(cat /opt/upgrade/out/rootfs_*/usr/share/mynode/version)
if [ $IS_X86 = 1 ] || [ $IS_RASPI4_ARM64 = 1 ]; then
    rsync -r -K /opt/upgrade/out/rootfs_${DEVICE_TYPE}/* / 2>&1
else
    cp -rf /opt/upgrade/out/rootfs_${DEVICE_TYPE}/* / 2>&1
fi
sleep 1
sync
sleep 1

VERSION=$(cat /usr/share/mynode/version)

# Clear old upgrade logs
rm -f /home/admin/upgrade_logs/upgrade_log_${VERSION}_post_*
rm -f /home/admin/upgrade_logs/upgrade_log_latest_post_*

# Run post upgrade script
touch $UPGRADE_ERROR_FILE
for i in {1..5}
do
    /bin/bash /usr/bin/mynode_post_upgrade.sh 2>&1
    RC=$?
    if [ "${RC}" -eq "0" ]; then
        rm -f $UPGRADE_ERROR_FILE
        break
    fi
    printf "\n\n\n"
    printf "##################################################\n"
    printf "Post upgrade script failed attempt $i. Retrying.  \n"
    printf "##################################################\n"
    printf "\n\n\n"
    sleep 10s
done
chown -R admin:admin /home/admin/upgrade_logs
sync