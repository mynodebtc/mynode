#!/bin/bash

source /usr/share/mynode/mynode_config.sh

mkdir -p /tmp/mynode_lndconnect/
cd /tmp/mynode_lndconnect/

echo "Starting lndconnect script..."

echo "Waiting on lnd wallet file..."
while [ ! -f $LND_WALLET_FILE ]; do
    sleep 1m
done
echo "LND Wallet found!"

while true; do
    echo "Generating lndconnect QR codes..."
    rm -rf /tmp/mynode_lndconnect/*

    # Generate QR Codes
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -o --bitcoin.mainnet
    cp -f lndconnect-qr.png lndconnect_remote_grpc.png
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -o --bitcoin.mainnet --localip
    cp -f lndconnect-qr.png lndconnect_local_grpc.png
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -o --bitcoin.mainnet -p 10080
    cp -f lndconnect-qr.png lndconnect_remote_rest.png
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -o --bitcoin.mainnet --localip -p 10080
    cp -f lndconnect-qr.png lndconnect_local_rest.png

    # Generate Text Files
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -j --bitcoin.mainnet > lndconnect_remote_grpc.txt
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -j --bitcoin.mainnet --localip > lndconnect_local_grpc.txt
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -j --bitcoin.mainnet -p 10080 > lndconnect_remote_rest.txt
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -j --bitcoin.mainnet --localip -p 10080 > lndconnect_local_rest.txt

    echo "Done! Waiting until LND changes, then regen lndconnect codes!"
    inotifywait -e modify -e create -e delete $LND_ADMIN_MACAROON_FILE
done

# Should never exit
exit 99