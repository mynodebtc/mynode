#!/bin/bash

# Turns automatic OS security updates on or off to match the
# "Automatically Install OS Security Updates" setting (on unless disabled).
# The policy (security updates only, no reboots) is in
# /etc/apt/apt.conf.d/90mynode-unattended-upgrades.

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_functions.sh

AUTO_UPGRADES_FILE="/etc/apt/apt.conf.d/90mynode-auto-upgrades"

ENABLED="1"
if settings_file_exists "unattended_upgrades_disabled"; then
    ENABLED="0"
fi
# Buster's repos are archived and no longer get security updates
if [ "$DEBIAN_CODENAME" = "buster" ]; then
    ENABLED="0"
fi

cat > "${AUTO_UPGRADES_FILE}.tmp" <<END
// Written by mynode_unattended_upgrades.sh - changes here are overwritten
APT::Periodic::Update-Package-Lists "${ENABLED}";
APT::Periodic::Unattended-Upgrade "${ENABLED}";
END
mv -f "${AUTO_UPGRADES_FILE}.tmp" "${AUTO_UPGRADES_FILE}"
sync

if [ "$ENABLED" = "1" ]; then
    systemctl enable --now apt-daily.timer apt-daily-upgrade.timer > /dev/null 2>&1 || true
    echo "Automatic OS security updates are on"
else
    echo "Automatic OS security updates are off"
fi
