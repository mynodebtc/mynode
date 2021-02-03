#!/bin/bash

# Message
echo "Stopping myNode services..."

# Mark we are shutting down
touch /tmp/shutting_down


# Stop additional services
systemctl stop glances lndhub netdata rtl webssh2 whirlpool dojo
systemctl stop btcpayserver btc_rpc_explorer specter caravan lnbits
systemctl stop thunderhub mempoolspace


# Manually stop services (backup)
if [ "$(systemctl is-active docker)" = "active" ]; then
    /mnt/hdd/mynode/dojo/docker/my-dojo/dojo.sh stop || true
fi


# Stop core services
systemctl stop electrs loopd lnd quicksync bitcoind


# Sync filesystem
sync
