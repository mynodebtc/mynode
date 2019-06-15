#!/bin/bash

# Wait to see if bitcoind is synced
echo "Checking if Bitcoin is synced..."
while [ ! -f "/mnt/hdd/mynode/.mynode_bitcoind_synced" ]; do
    echo "Bitcoin not synced, sleeping for 60 seconds..."
    /bin/sleep 60s
done

# And finally, make sure bitcoind responds to API requests
bitcoin-cli -rpcwait getblockchaininfo

exit 0