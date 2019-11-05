#!/bin/bash

# Generate BTC Config
if [ -f /mnt/hdd/mynode/settings/bitcoin_custom.conf ]; then
    cp -f /mnt/hdd/mynode/settings/bitcoin_custom.conf /mnt/hdd/mynode/bitcoin/bitcoin.conf
else
    cp -f /usr/share/mynode/bitcoin.conf /mnt/hdd/mynode/bitcoin/bitcoin.conf
fi

PW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
RPCAUTH=$(gen_rpcauth.py mynode $PW)
#sed -i "s/rpcpassword=.*/rpcpassword=$PW/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
sed -i "s/rpcauth=.*/$RPCAUTH/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf

cp -f /mnt/hdd/mynode/bitcoin/bitcoin.conf /home/admin/.bitcoin/bitcoin.conf
chown bitcoin:bitcoin /mnt/hdd/mynode/bitcoin/bitcoin.conf
chown admin:admin /home/admin/.bitcoin/bitcoin.conf
