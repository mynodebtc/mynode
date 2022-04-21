#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

# Update Bitcoin RPC Password
BTCRPCPW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
if [ -f /mnt/hdd/mynode/btcpayserver/.env ]; then
    sed -i "s/REMOTE_BTC_RPC_PASSWORD=.*/REMOTE_BTC_RPC_PASSWORD=$BTCRPCPW/g" /mnt/hdd/mynode/btcpayserver/.env
fi
