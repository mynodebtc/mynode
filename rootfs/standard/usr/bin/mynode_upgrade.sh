#!/bin/bash

set -x
#set -e

source /usr/share/mynode/mynode_config.sh

BETA=0
EXPECTED_VERSION=""
while test $# -gt 0
do
    case "$1" in
        beta) echo "Installing a beta..."
            BETA=1
            ;;
        expect) shift
            EXPECTED_VERSION="$1"
            echo "Expecting version ${EXPECTED_VERSION}..."
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

VERIFIED=0
for KEY in /usr/share/mynode/mynode_release.pub /usr/share/mynode/mynode_release_backup.pub; do
    if openssl dgst -sha256 -verify $KEY -signature /opt/mynode_release_latest.sha256 /opt/mynode_release_latest.tar.gz; then
        VERIFIED=1
        break
    fi
done
if [ $VERIFIED -ne 1 ]; then
    echo "UPGRADE FAILED! Hash did not match!" >> /var/log/upgrade.log
    exit 1
fi

# Extract to temp location
tar -xf /opt/mynode_release_latest.tar.gz -C /opt/upgrade/

# Stop before changing anything if the download is not the expected version (exit 3)
VERSION=$(cat /opt/upgrade/out/rootfs_${DEVICE_TYPE}/usr/share/mynode/version)
if [ "$EXPECTED_VERSION" != "" ] && [ "$VERSION" != "$EXPECTED_VERSION" ]; then
    echo "UPGRADE STOPPED! Downloaded version '${VERSION}' is not ${EXPECTED_VERSION}" >> /var/log/upgrade.log
    exit 3
fi

# Marks the upgrade as incomplete until the post upgrade script succeeds
touch $UPGRADE_ERROR_FILE

# Clear beta install marking
rm -f /usr/share/mynode/beta_version

# Clear files before installing/overwriting new ones
rm -rf /var/www/mynode/static/images/screenshots
for d in /usr/share/mynode_apps/*/screenshots ; do
    rm -rf "$d"
done

# Install files (migrate all to rsync?)
if [ $IS_X86 = 1 ] || [ $IS_ARM64 = 1 ] || [ $IS_ROCKPI4 = 1 ] || [ $IS_RASPI5 = 1 ]; then
    rsync -r -K /opt/upgrade/out/rootfs_${DEVICE_TYPE}/* / 2>&1
else
    cp -rf /opt/upgrade/out/rootfs_${DEVICE_TYPE}/* / 2>&1
fi
sleep 1
sync /
sleep 1

VERSION=$(cat /usr/share/mynode/version)

# Clear old upgrade logs
rm -f /home/admin/upgrade_logs/upgrade_log_${VERSION}_post_*
rm -f /home/admin/upgrade_logs/upgrade_log_latest_post_*

# Run post upgrade script
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