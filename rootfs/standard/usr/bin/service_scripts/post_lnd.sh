#!/bin/bash

sleep 10s

# Set folders +x so files can be navigated by bitcoin group
chmod +x /mnt/hdd/mynode/lnd/data || true
chmod +x /mnt/hdd/mynode/lnd/data/chain || true
chmod +x /mnt/hdd/mynode/lnd/data/chain/bitcoin || true
chmod +x /mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet || true

# New files should be 640, if it already exists update it so bitcoin group can read macaroon
if [ -f /mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon ]; then
    chmod 640 /mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon
fi

exit 0