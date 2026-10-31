#!/bin/bash

# Installs updates for the OS packages without upgrading MyNode itself

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_config.sh

set -x
set -e

# Make sure time is in the log
date

# Check if upgrades use tor
TORIFY=""
if [ -f /mnt/hdd/mynode/settings/torify_apt_get ]; then
    TORIFY="torify"
fi

export DEBIAN_FRONTEND=noninteractive
APT_OPTIONS="-o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Check if any dpkg installs have failed and correct
dpkg --configure -a --force-confdef --force-confold

# Check for updates
$TORIFY apt-get $APT_OPTIONS update --allow-releaseinfo-change || \
        apt-get $APT_OPTIONS update --allow-releaseinfo-change

# Freeze any packages we don't want to update
if [ $IS_X86 = 1 ]; then
    apt-mark hold grub*
fi

# Upgrade packages, keeping MyNode's changes to config files
# Permit new dependencies (including kernel ABI packages), but not removals.
$TORIFY apt-get $APT_OPTIONS --with-new-pkgs -y upgrade

echo "OS packages upgraded"
