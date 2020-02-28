#!/bin/bash

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

ALIAS=$(cat /mnt/hdd/mynode/settings/.lndalias)
sed -i "s/alias=.*/alias=$ALIAS/g" /mnt/hdd/mynode/lnd/lnd.conf
chown bitcoin:bitcoin /mnt/hdd/mynode/lnd/lnd.conf