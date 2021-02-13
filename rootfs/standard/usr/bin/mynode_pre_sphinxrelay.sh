#!/bin/bash

set -x
set -e

LOCAL_IP_ADDR=$(hostname -I | head -n 1 | cut -d' ' -f1)

# Update IP address in config file (local IP)
if [ -f /mnt/hdd/mynode/sphinxrelay/app.json ]; then
    sed -i "s/public_url\": \".*/public_url\": \"${LOCAL_IP_ADDR}:53001\",/g" /mnt/hdd/mynode/sphinxrelay/app.json
fi

exit 0