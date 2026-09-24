#!/bin/bash

set -x
set -e

LOCAL_IP_ADDR=$(hostname -I | head -n 1 | cut -d' ' -f1)
SPHINX_TOR_ADDR=""
if [ -f /var/lib/tor/mynode_sphinx/hostname ]; then
    SPHINX_TOR_ADDR=$(cat /var/lib/tor/mynode_sphinx/hostname)
fi

# Update URL in config file (tor address)
if [ -f /mnt/hdd/mynode/sphinxrelay/app.json ] && [ "$SPHINX_TOR_ADDR" != "" ]; then
    sed -i "s/public_url\": \".*/public_url\": \"${SPHINX_TOR_ADDR}:53001\",/g" /mnt/hdd/mynode/sphinxrelay/app.json
fi

exit 0