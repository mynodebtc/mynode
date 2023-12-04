#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

apt -y update

mkdir -p $VPN_BACKUP_DIR

while [ true ]; do
    # Check for backup files
    if [ ! -f /home/pivpn/ovpns/mynode_vpn.ovpn ]; then
        if [ -f $VPN_BACKUP_DIR/mynode_vpn.ovpn ]; then
            cp $VPN_BACKUP_DIR/mynode_vpn.ovpn /home/pivpn/ovpns/mynode_vpn.ovpn
        fi
        if [ -d $VPN_BACKUP_DIR/openvpn ]; then
            cp -rf $VPN_BACKUP_DIR/openvpn /etc
        fi
    fi

    # Generate new files
    if [ ! -f /home/pivpn/ovpns/mynode_vpn.ovpn ]; then
        /usr/bin/mynode_setup_vpn.sh

        mkdir -p /home/pivpn/ovpns
        pivpn add -n mynode_vpn nopass -d 3650

        # Backup files to HDD
        sync
        cp -rf /etc/openvpn/ $VPN_BACKUP_DIR/
        cp /home/pivpn/ovpns/mynode_vpn.ovpn $VPN_BACKUP_DIR/mynode_vpn.ovpn
    fi

    systemctl enable openvpn
    systemctl start openvpn
    sleep 365d
done