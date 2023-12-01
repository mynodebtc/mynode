#!/bin/bash

# Message
echo "Stopping MyNode services..."

# Mark we are shutting down
touch /tmp/shutting_down

# Stop dynamic apps
date
mynode-manage-apps stop

# Stop additional services
date
systemctl stop glances lndhub netdata rtl webssh2 whirlpool dojo
date
systemctl stop btcpayserver btcrpcexplorer specter caravan lnbits
date
systemctl stop thunderhub mempool  
date


# Manually stop services (backup)
if [ "$(systemctl is-active docker)" = "active" ]; then
    /mnt/hdd/mynode/dojo/docker/my-dojo/dojo.sh stop || true
fi


# Stop core services
date
systemctl stop electrs loop pool lnd quicksync
date
killall bitcoind || true
systemctl stop bitcoin
date


# Sync filesystem
sync

echo "Done stopping services."