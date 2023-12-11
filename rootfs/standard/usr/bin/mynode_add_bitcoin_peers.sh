#!/bin/bash

set -x
set -e

# Try to get peer info - if it fails serice will restart until bitcoin is ready
bitcoin-cli getpeerinfo

# Give bitcoin some time to start
sleep 1m

# Check if btc has peers
while true; do
    echo "Checking Bitcoin peer count..."
    PEER_COUNT=$(bitcoin-cli getpeerinfo | jq '. | length')
    if [ "$PEER_COUNT" -lt "6" ]; then
        echo "$PEER_COUNT peers. Try adding one."

        echo -n "" > /tmp/new_peer
        if [ -f /mnt/hdd/mynode/settings/btc_ipv4_enabled ] || [ -f /home/bitcoin/.mynode/btc_ipv4_enabled ]; then
            RANDOM_PEER=$(shuf /usr/share/mynode/bitcoin_peers.txt | egrep "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n 1)
            echo "$RANDOM_PEER" >> /tmp/new_peer
        fi
        if [ -f /mnt/hdd/mynode/settings/btc_tor_enabled ] || [ -f /home/bitcoin/.mynode/btc_tor_enabled ]; then
            RANDOM_PEER=$(shuf /usr/share/mynode/bitcoin_peers.txt | grep ".onion" | head -n 1)
            echo "$RANDOM_PEER" >> /tmp/new_peer
        fi
        if [ -f /mnt/hdd/mynode/settings/btc_i2p_enabled ] || [ -f /home/bitcoin/.mynode/btc_i2p_enabled ]; then
            RANDOM_PEER=$(shuf /usr/share/mynode/bitcoin_peers.txt | grep "b32.i2p:0" | head -n 1)
            echo "$RANDOM_PEER" >> /tmp/new_peer
        fi
        RANDOM_PEER=$(shuf /tmp/new_peer | head -n 1)

        echo "Attempting to add peer $RANDOM_PEER"
        bitcoin-cli addnode "$RANDOM_PEER" "onetry"

        sleep 10s
    else
        echo "We have $PEER_COUNT peers!"
        sleep 60m
    fi
done