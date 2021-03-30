#!/bin/bash

source /usr/share/mynode/mynode_config.sh

# Check if testnet
if [ -f $IS_TESTNET_ENABLED_FILE ]; then
    exit 1
fi

# We are on mainnet (exit success)
exit 0