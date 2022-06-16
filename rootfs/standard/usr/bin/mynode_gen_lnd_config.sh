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

    # Append Watchtower Server Section
    if [ -f /mnt/hdd/mynode/settings/watchtower_enabled ]; then
        cat /usr/share/mynode/lnd_watchtower.conf >> /mnt/hdd/mynode/lnd/lnd.conf
    fi

    # Append Watchtower Client Section
    if [ -f /mnt/hdd/mynode/settings/watchtower_client_enabled ]; then
        cat /usr/share/mynode/lnd_watchtower_client.conf >> /mnt/hdd/mynode/lnd/lnd.conf
    fi

    # Append Tor/IP section (check new file or old file, should be migrated to new)
    if [ -f /mnt/hdd/mynode/settings/btc_lnd_tor_enabled ] || [ -f /home/bitcoin/.mynode/btc_lnd_tor_enabled ]; then
        cat /usr/share/mynode/lnd_tor.conf >> /mnt/hdd/mynode/lnd/lnd.conf

        # Upadte LND Tor stream isolation (true is default)
        if [ -f /mnt/hdd/mynode/settings/streamisolation_tor_disabled ]; then
            sed -i "s/tor.streamisolation=.*/tor.streamisolation=false/g" /mnt/hdd/mynode/lnd/lnd.conf
        fi
    else
        cat /usr/share/mynode/lnd_ipv4.conf >> /mnt/hdd/mynode/lnd/lnd.conf
    fi

    # Append Mainnet/Testnet section
    if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
        sed -i "s/bitcoin.mainnet=.*/bitcoin.mainnet=0/g" /mnt/hdd/mynode/lnd/lnd.conf
        sed -i "s/bitcoin.testnet=.*/bitcoin.testnet=1/g" /mnt/hdd/mynode/lnd/lnd.conf
        cat /usr/share/mynode/lnd_testnet.conf >> /mnt/hdd/mynode/lnd/lnd.conf
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