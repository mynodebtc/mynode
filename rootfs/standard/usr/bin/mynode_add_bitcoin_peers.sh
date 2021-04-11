#!/bin/bash

set -x
set -e

# Try to get peer info - if it fails serice will restart until bitcoin is ready
bitcoin-cli getpeerinfo

# Give bitcoin some time to start
sleep 2m

# Check if btc has peers
while true; do
    echo "Checking Bitcoin peer count..."
    PEER_COUNT=$(bitcoin-cli getpeerinfo | grep "id" | wc -l)
    if [ "$PEER_COUNT" -lt "3" ]; then
        echo "$PEER_COUNT peers. Try adding one."

        RANDOM_PEER=$(shuf /usr/share/mynode/bitcoin_peers.txt | head -n 1)
        echo "Attempting to add peer $RANDOM_PEER"
        
        bitcoin-cli addnode "$RANDOM_PEER" "onetry"

        sleep 1m
    else
        echo "We have $PEER_COUNT peers!"
        sleep 60m
    fi
done