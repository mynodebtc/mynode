#!/bin/bash

set -x
set -e

LOCAL_IP_ADDR=$(hostname -I | head -n 1 | cut -d' ' -f1)
SPHINX_TOR_ADDR=""
if [ -f /var/lib/tor/mynode_sphinx/hostname ]; then
    SPHINX_TOR_ADDR=$(cat /var/lib/tor/mynode_sphinx/hostname)
fi

# Update URL in config file (tor address, or the local IP when Tor remote access is off)
SPHINX_PUBLIC_ADDR="$LOCAL_IP_ADDR"
if [ "$SPHINX_TOR_ADDR" != "" ] && [ ! -f /mnt/hdd/mynode/settings/tor_remote_access_disabled ] && [ ! -f /home/bitcoin/.mynode/tor_remote_access_disabled ]; then
    SPHINX_PUBLIC_ADDR="$SPHINX_TOR_ADDR"
fi
if [ -f /mnt/hdd/mynode/sphinxrelay/app.json ] && [ "$SPHINX_PUBLIC_ADDR" != "" ]; then
    sed -i "s/public_url\": \".*/public_url\": \"${SPHINX_PUBLIC_ADDR}:53001\",/g" /mnt/hdd/mynode/sphinxrelay/app.json
fi

# Use the macaroon baked for Sphinx Relay before this runs
SPHINXRELAY_MACAROON=/mnt/hdd/mynode/lnd/sphinxrelay.macaroon
if [ -f /mnt/hdd/mynode/sphinxrelay/app.json ]; then
    sed -i "s|\"macaroon_location\": \"/home/bitcoin/.lnd/data/chain/bitcoin/mainnet/admin.macaroon\"|\"macaroon_location\": \"$SPHINXRELAY_MACAROON\"|g" /mnt/hdd/mynode/sphinxrelay/app.json
fi

# Listen on 127.0.0.1 only; nginx serves 53001. The relay has no setting for this.
SPHINXRELAY_APP=/opt/mynode/sphinxrelay/dist/app.js
if [ -f $SPHINXRELAY_APP ]; then
    sed -i "s/server.listen(port, (err) =>/server.listen(port, '127.0.0.1', (err) =>/" $SPHINXRELAY_APP
    if ! grep -q "server.listen(port, '127.0.0.1'," $SPHINXRELAY_APP; then
        echo "WARNING: Unable to limit Sphinx Relay to 127.0.0.1"
    fi
fi

exit 0