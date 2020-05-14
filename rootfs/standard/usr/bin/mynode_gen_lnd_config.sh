#!/bin/bash

# Setup Initial LND Node Name
if [ ! -f /mnt/hdd/mynode/settings/.lndalias ]; then
    echo "mynodebtc.com [myNode]" > /mnt/hdd/mynode/settings/.lndalias
fi

# Generate LND Config
if [ -f /mnt/hdd/mynode/settings/lnd_custom.conf ]; then
    # Use Custom Config
    cp -f /mnt/hdd/mynode/settings/lnd_custom.conf /mnt/hdd/mynode/lnd/lnd.conf
else
    # Generate a default config
    cp -f /usr/share/mynode/lnd.conf /mnt/hdd/mynode/lnd/lnd.conf

    # Append other sections
    if [ -f /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled ]; then
        cat /usr/share/mynode/lnd_tor.conf >> /mnt/hdd/mynode/lnd/lnd.conf
    else
        cat /usr/share/mynode/lnd_ipv4.conf >> /mnt/hdd/mynode/lnd/lnd.conf
    fi
fi

# Append tor domain
if [ -f /var/lib/tor/mynode_lnd/hostname ]; then
    echo "" >> /mnt/hdd/mynode/lnd/lnd.conf
    echo "[Application Options]" >> /mnt/hdd/mynode/lnd/lnd.conf
    ONION_URL=$(cat /var/lib/tor/mynode_lnd/hostname)
    echo "tlsextradomain=$ONION_URL" >> /mnt/hdd/mynode/lnd/lnd.conf
    echo "" >> /mnt/hdd/mynode/lnd/lnd.conf
fi

ALIAS=$(cat /mnt/hdd/mynode/settings/.lndalias)
sed -i "s/alias=.*/alias=$ALIAS/g" /mnt/hdd/mynode/lnd/lnd.conf
chown bitcoin:bitcoin /mnt/hdd/mynode/lnd/lnd.conf