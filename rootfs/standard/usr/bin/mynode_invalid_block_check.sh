#!/bin/bash

sleep 5m

while [ 1 ]; do
    if [ -f /mnt/hdd/mynode/bitcoin/debug.log ]; then
        log=$(tail -n 10 /mnt/hdd/mynode/bitcoin/debug.log | grep "ERROR: AcceptBlockHeader")
        if [ $? == 0 ]; then
            block=$(tail -n 10 /mnt/hdd/mynode/bitcoin/debug.log | grep "ERROR: AcceptBlockHeader" | tail -n 1 | egrep -o "block [0-9a-f]+" | awk '{print $2}')
            echo "INVALID BLOCK FOUND: $block"
            echo "Fixing..."
            bitcoin-cli -rpccookiefile=/mnt/hdd/mynode/bitcoin/.cookie invalidateblock $block
            bitcoin-cli -rpccookiefile=/mnt/hdd/mynode/bitcoin/.cookie reconsiderblock $block
            echo "Done fixing block $block"
            sleep 30m
        fi
    fi
    sleep 5m
done