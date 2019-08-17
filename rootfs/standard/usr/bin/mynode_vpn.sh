#!/bin/bash

apt -y update

while [ true ]; do
    if [ ! -f /home/pivpn/ovpns/mynode_vpn.ovpn ]; then
        /usr/bin/mynode_setup_vpn.sh

        mkdir -p /home/pivpn/ovpns
        pivpn add -n mynode_vpn nopass -d 3650
    fi

    systemctl enable openvpn
    systemctl start openvpn
    sleep 365d
done