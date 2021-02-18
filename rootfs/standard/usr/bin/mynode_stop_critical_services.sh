#!/bin/bash

# Message
echo "Stopping myNode services..."

# Mark we are shutting down
touch /tmp/shutting_down


# Stop additional services
date
systemctl stop glances lndhub netdata rtl webssh2 whirlpool dojo
date
systemctl stop btcpayserver btc_rpc_explorer specter caravan lnbits
date
systemctl stop thunderhub mempoolspace
date


# Manually stop services (backup)
if [ "$(systemctl is-active docker)" = "active" ]; then
    /mnt/hdd/mynode/dojo/docker/my-dojo/dojo.sh stop || true
fi


# Stop core services
date
systemctl stop electrs loopd lnd quicksync
date
killall bitcoind || true
systemctl stop bitcoind
date


# Sync filesystem
sync

echo "Done stopping services."