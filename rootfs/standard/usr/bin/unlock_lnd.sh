#!/bin/bash

source /usr/share/mynode/mynode_config.sh

# NOTE: NO LONGER USED AFTER LND 0.13+

# Wait for LND + BTC to start
sleep 1m

CHECK_RATE="10s"

while true; do

    while [ ! -f "$LND_WALLET_FILE" ]; do
        echo "Waiting for LND wallet file to exist..."
        sleep 30s
    done

    while [ ! -f "$LND_ADMIN_MACAROON_FILE" ]; do
        echo "Waiting for LND admin macaroon file to exist..."
        sleep 30s
    done

    # Wait for lnd to accept logins
    until journalctl -r -u lnd --no-pager | head -n 20 | grep "wallet locked, unlock it to enable full RPC access"
    do
        sleep $CHECK_RATE
    done
    sleep 5s

    echo "Unlocking wallet..."
    /usr/bin/expect /usr/bin/unlock_lnd.tcl
    if [ $? -eq 0 ]; then
        # Unlocked! Verify unlocked every time LND files change
        inotifywait -t 600 -r -e modify -e create -e delete /mnt/hdd/mynode/lnd/data/chain/bitcoin/ /mnt/hdd/mynode/lnd/tls.cert
        
        # Slow down check rate for next time around
        CHECK_RATE="60s"
    else
        # Failed, try again in 15 seconds
        /bin/sleep 15s
    fi
done

exit 0