#!/bin/bash

# Setup Initial LND Node Name
if [ ! -f /mnt/hdd/mynode/settings/.lndalias ]; then
    echo "mynodebtc.com [myNode]" > /mnt/hdd/mynode/settings/.lndalias
fi

# Generate Lightning Terminal Config
if [ -f /mnt/hdd/mynode/settings/lit_custom.conf ]; then
    # Use Custom Config
    cp -f /mnt/hdd/mynode/settings/lit_custom.conf /mnt/hdd/mynode/lit/lit.conf
else
    # Generate a default config
    cp -f /usr/share/mynode/lit.conf /mnt/hdd/mynode/lit/lit.conf

    # Append other sections
    if [ -f /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled ]; then
        cat /usr/share/mynode/lit_tor.conf >> /mnt/hdd/mynode/lit/lit.conf
    else
        cat /usr/share/mynode/lit_ipv4.conf >> /mnt/hdd/mynode/lit/lit.conf
    fi

    # Append Mainnet/Testnet section
    if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
        sed -i "s/mainnet/testnet/g" /mnt/hdd/mynode/lit/lnd.conf
        sed -i "s/bitcoin.testnet=.*/bitcoin.testnet=1/g" /mnt/hdd/mynode/lnd/lnd.conf
        cat /usr/share/mynode/lnd_testnet.conf >> /mnt/hdd/mynode/lnd/lnd.conf
    fi
fi

# Append tor domain
if [ -f /var/lib/tor/mynode_lnd/hostname ]; then
    echo "" >> /mnt/hdd/mynode/lit/lit.conf
    ONION_URL=$(cat /var/lib/tor/mynode_lnd/hostname)
    echo "lnd.tlsextradomain=$ONION_URL" >> /mnt/hdd/mynode/lit/lit.conf
    echo "" >> /mnt/hdd/mynode/lit/lit.conf
fi

ALIAS=$(cat /mnt/hdd/mynode/settings/.lndalias)
sed -i "s/lnd.alias=.*/lnd.alias=$ALIAS/g" /mnt/hdd/mynode/lit/lit.conf
chown bitcoin:bitcoin /mnt/hdd/mynode/lit/lit.conf