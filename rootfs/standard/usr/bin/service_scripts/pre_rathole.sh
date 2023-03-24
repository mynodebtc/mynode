#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

mkdir -p /opt/mynode/rathole

# Delay start if premium+ not setup
if [ ! -f /home/bitcoin/.mynode/.premium_plus_token ]; then
    echo "No Premium+ Token. Sleeping 20s."
    sleep 20s
    exit 1
fi

# Generate a placeholder config
if [ ! -f /opt/mynode/rathole/client.toml ]; then

    cat << EOF > /opt/mynode/rathole/client.toml
# client.toml
[client]
remote_addr = "localhost:2333"
retry_interval = 600

[client.services.nonsense]
local_addr = "127.0.0.1:443"
token = "MISSING_TOKEN"

EOF

fi