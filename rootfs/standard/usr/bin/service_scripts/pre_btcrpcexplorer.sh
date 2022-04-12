#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

# Initialize BTC RPC Explorer Config
mkdir -p /opt/mynode/btc-rpc-explorer
cp /usr/share/mynode/btcrpcexplorer_env /opt/mynode/btc-rpc-explorer/.env
chown -R bitcoin:bitcoin /opt/mynode/btc-rpc-explorer

# Update Bitcoin RPC Password
BTCRPCPW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
if [ -f /opt/mynode/btc-rpc-explorer/.env ]; then
    sed -i "s/BTCEXP_BITCOIND_PASS=.*/BTCEXP_BITCOIND_PASS=$BTCRPCPW/g" /opt/mynode/btc-rpc-explorer/.env
fi

# Enable / disable token requirement
if [ -f /mnt/hdd/mynode/settings/.btcrpcexplorer_disable_token ]; then
    sed -i "s/BTCEXP_SSO_TOKEN_FILE/#BTCEXP_SSO_TOKEN_FILE/g" /opt/mynode/btc-rpc-explorer/.env
fi
