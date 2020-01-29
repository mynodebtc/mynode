#!/bin/bash

# Setup default settings
if [ ! -f /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled_defaulted ]; then
    touch /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled_defaulted
    touch /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled
    sync
fi

# Generate BTC Config
if [ -f /mnt/hdd/mynode/settings/bitcoin_custom.conf ]; then
    # Use Custom Config
    cp -f /mnt/hdd/mynode/settings/bitcoin_custom.conf /mnt/hdd/mynode/bitcoin/bitcoin.conf
else
    # Generate a default config
    cp -f /usr/share/mynode/bitcoin.conf /mnt/hdd/mynode/bitcoin/bitcoin.conf

    # Append other sections
    if [ -f /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled ]; then
        cat /usr/share/mynode/bitcoin_tor.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    else
        cat /usr/share/mynode/bitcoin_ipv4.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi
fi

PW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
RPCAUTH=$(gen_rpcauth.py mynode $PW)
#sed -i "s/rpcpassword=.*/rpcpassword=$PW/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
sed -i "s/rpcauth=.*/$RPCAUTH/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf

cp -f /mnt/hdd/mynode/bitcoin/bitcoin.conf /home/admin/.bitcoin/bitcoin.conf
chown bitcoin:bitcoin /mnt/hdd/mynode/bitcoin/bitcoin.conf
chown admin:admin /home/admin/.bitcoin/bitcoin.conf
