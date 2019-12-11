#!/bin/bash

set -x
set -e

# Wait to see if bitcoind is synced
echo "Checking if electrum server is ready is synced..."
while [ ! -f "/tmp/electrs_up_to_date" ]; do
    echo "electrs not synced, sleeping 1m"
    /bin/sleep 30s
done

exit 0