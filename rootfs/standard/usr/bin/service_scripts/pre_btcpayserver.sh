#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

# Update Bitcoin RPC Credentials
BTCRPCPW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
NBXPLORER_VARIABLES_FILE=/mnt/hdd/mynode/btcpayserver/btcpayserver-docker/Generated/nbxplorer-variables.env
echo "NBXPLORER_BTCRPCUSER=mynode"            > $NBXPLORER_VARIABLES_FILE
echo "NBXPLORER_BTCRPCPASSWORD=$BTCRPCPW"    >> $NBXPLORER_VARIABLES_FILE
