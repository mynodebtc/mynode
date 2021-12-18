#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x
set -e

# RTL config
sudo -u bitcoin mkdir -p /opt/mynode/RTL
sudo -u bitcoin mkdir -p /mnt/hdd/mynode/rtl
chown -R bitcoin:bitcoin /mnt/hdd/mynode/rtl
chown -R bitcoin:bitcoin /mnt/hdd/mynode/rtl_backup

# If local settings file is not a symlink, delete and setup symlink to HDD
if [ ! -L /opt/mynode/RTL/RTL-Config.json ]; then
    rm -f /opt/mynode/RTL/RTL-Config.json
    sudo -u bitcoin ln -s /mnt/hdd/mynode/rtl/RTL-Config.json /opt/mynode/RTL/RTL-Config.json
fi

# If config file on HDD does not exist, create it
if [ ! -f /mnt/hdd/mynode/rtl/RTL-Config.json ]; then
    cp -f /usr/share/mynode/RTL-Config.json /mnt/hdd/mynode/rtl/RTL-Config.json
fi

# Force update of RTL config file (increment to force new update)
RTL_CONFIG_UPDATE_NUM=1
if [ ! -f /mnt/hdd/mynode/rtl/update_settings_$RTL_CONFIG_UPDATE_NUM ]; then
    cp -f /usr/share/mynode/RTL-Config.json /mnt/hdd/mynode/rtl/RTL-Config.json
    touch /mnt/hdd/mynode/rtl/update_settings_$RTL_CONFIG_UPDATE_NUM
fi

# Update RTL config file to use mynode pw
if [ -f /home/bitcoin/.mynode/.hashedpw ]; then
    HASH=$(cat /home/bitcoin/.mynode/.hashedpw)
    sed -i "s/\"multiPassHashed\":.*/\"multiPassHashed\": \"$HASH\",/g" /mnt/hdd/mynode/rtl/RTL-Config.json
fi

# Update for testnet
if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
    sed -i "s/mainnet/testnet/g" /mnt/hdd/mynode/rtl/RTL-Config.json || true
else
    sed -i "s/testnet/mainnet/g" /mnt/hdd/mynode/rtl/RTL-Config.json || true
fi

sync
sleep 3s