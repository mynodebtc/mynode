#!/bin/bash

# Installs updates for the OS packages without upgrading MyNode itself

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_functions.sh

set -x
set -e

# Make sure time is in the log
date

export DEBIAN_FRONTEND=noninteractive
APT_OPTIONS="-o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Don't let automatic OS security updates use apt at the same time
pause_automatic_os_updates
trap "systemctl start apt-daily.timer apt-daily-upgrade.timer > /dev/null 2>&1 || true" EXIT

# Check if any dpkg installs have failed and correct
dpkg --configure -a --force-confdef --force-confold

# Check for updates
apt-get $APT_OPTIONS update --allow-releaseinfo-change || \
        apt-get $APT_OPTIONS update --allow-releaseinfo-change

# Freeze any packages we don't want to update
if [ $IS_X86 = 1 ]; then
    apt-mark hold grub*
fi

# Upgrade packages, including new kernels, keeping MyNode's changes to config files
apt-get $APT_OPTIONS -y --with-new-pkgs upgrade

echo "OS packages upgraded"
