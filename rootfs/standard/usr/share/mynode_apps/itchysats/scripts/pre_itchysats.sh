#!/bin/bash

# This will run prior to launching the application

source /usr/share/mynode/mynode_config.sh

NETWORK=mainnet
if [ -f $IS_TESTNET_ENABLED_FILE ]; then
    NETWORK=testnet
fi

# Ensure that data directory for ${NETWORK} exists
sudo -u bitcoin mkdir -p /mnt/hdd/mynode/itchysats/${NETWORK}/data

# Ensure that environment variables are available for itchysats.service
sudo -u bitcoin echo -n "" >/mnt/hdd/mynode/itchysats/env

sudo -u bitcoin echo "ITCHYSATS_ENV=mynode" >> /mnt/hdd/mynode/itchysats/env

port=$(jq .http_port /usr/share/mynode_apps/itchysats/itchysats.json)
sudo -u bitcoin echo "HTTP_ADDRESS=127.0.0.1:${port}" >> /mnt/hdd/mynode/itchysats/env

sudo -u bitcoin echo "NETWORK=${NETWORK}" >> /mnt/hdd/mynode/itchysats/env

sudo -u bitcoin echo "DATA_DIR=/mnt/hdd/mynode/itchysats/${NETWORK}/data" >> /mnt/hdd/mynode/itchysats/env

# The port number matches the one defined in /mnt/hdd/mynode/electrs/electrs.toml
sudo -u bitcoin echo "ELECTRUM_RPC_ADDRESS=tcp://127.0.0.1:50001" >> /mnt/hdd/mynode/itchysats/env
