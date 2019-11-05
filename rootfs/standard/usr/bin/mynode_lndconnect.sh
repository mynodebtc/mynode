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
echo "Waiting on admin macaroon..."
while [ ! -f $LND_ADMIN_MACAROON_FILE ]; do
    sleep 15s
done
echo "Admin macroon found!"
sleep 5s

while true; do
    echo "Generating lndconnect QR codes..."
    rm -rf /tmp/mynode_lndconnect/*

    while [ ! -f $LND_ADMIN_MACAROON_FILE ] || [ ! -f $LND_WALLET_FILE ] || [ ! -f $LND_TLS_CERT_FILE ]; do
        sleep 15s
    done

    # Find URLs
    LND_TOR_ADDR=$(cat /var/lib/tor/mynode/hostname | awk '{print $1}')

    # Generate QR Codes
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -o --bitcoin.mainnet --localip
    cp -f lndconnect-qr.png lndconnect_local_grpc.png
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -o --bitcoin.mainnet --localip -p 10080
    cp -f lndconnect-qr.png lndconnect_local_rest.png
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -o --bitcoin.mainnet --host=$LND_TOR_ADDR
    cp -f lndconnect-qr.png lndconnect_tor_grpc.png
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -o --bitcoin.mainnet --host=$LND_TOR_ADDR -p 10080
    cp -f lndconnect-qr.png lndconnect_tor_rest.png

    # Generate Text Files
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -j --bitcoin.mainnet --localip > lndconnect_local_grpc.txt
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -j --bitcoin.mainnet --localip -p 10080 > lndconnect_local_rest.txt
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -j --bitcoin.mainnet --host=$LND_TOR_ADDR > lndconnect_tor_grpc.txt
    lndconnect --lnddir=/mnt/hdd/mynode/lnd -j --bitcoin.mainnet --host=$LND_TOR_ADDR -p 10080 > lndconnect_tor_rest.txt

    echo "Done! Waiting until LND changes, then regen lndconnect codes!"
    inotifywait -e modify -e create -e delete $LND_TLS_CERT_FILE $LND_ADMIN_MACAROON_FILE
done

# Should never exit
exit 99