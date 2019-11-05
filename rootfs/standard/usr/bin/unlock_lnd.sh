#!/bin/bash

source /usr/share/mynode/mynode_config.sh

while true; do

    while [ ! -f "$LND_WALLET_FILE" ]; do
        echo "Waiting for LND wallet file to exist..."
        sleep 30s
    done

    while [ ! -f "$LND_ADMIN_MACAROON_FILE" ]; do
        echo "Waiting for LND admin macaroon file to exist..."
        sleep 30s
    done

    # Sleep 15 seconds to let LND startup and avoid LN race condition
    # See https://github.com/lightningnetwork/lnd/issues/3631
    /bin/sleep 15s

    echo "Unlocking wallet..."
    /usr/bin/expect /usr/bin/unlock_lnd.tcl
    if [ $? -eq 0 ]; then
        # Unlocked! Verify unlocked every time LND files change
        inotifywait -r -e modify -e create -e delete /mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/
    else
        # Failed, try again in 15 seconds
        /bin/sleep 15s
    fi
done

exit 0