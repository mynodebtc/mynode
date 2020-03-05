#!/bin/bash

# Generate LND Config
if [ -f /mnt/hdd/mynode/settings/lnd_custom.conf ] || [ -f /mnt/hdd/mynode/settings/.lndalias ]; then
    # Set the alias value
    # TODO: Currently the alias value can only be set from the UI text box on
    # the /lnd page. If you try and set the alias value from editing the config
    # directly from lnd/config and the `/mnt/hdd/mynode/settings/.lndalias` file
    # exists then it will always get overwritten on boot. Fix this so it can be
    # edited from both locations.
    #
    # TODO: If the user deletes the alias key from the config and then later
    # decides to set a new alias from the /lnd page the value won't be set. Fix
    # this so the value is always set and not dependent on a regex search for
    # the word "alias=" already existing in the conf.
    if [ -f /mnt/hdd/mynode/settings/.lndalias ]; then
        ALIAS=$(cat /mnt/hdd/mynode/settings/.lndalias)
        sed -i "s/alias=.*/alias=$ALIAS/g" /mnt/hdd/mynode/settings/lnd_custom.conf
    fi

    # Use a custom config
    cp -f /mnt/hdd/mynode/settings/lnd_custom.conf /mnt/hdd/mynode/lnd/lnd.conf
else
    # Use the default config
    cp -f /usr/share/mynode/lnd.conf /mnt/hdd/mynode/lnd/lnd.conf
fi

# Append other sections
if [ -f /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled ]; then
    cat /usr/share/mynode/lnd_tor.conf >> /mnt/hdd/mynode/lnd/lnd.conf
else
    cat /usr/share/mynode/lnd_ipv4.conf >> /mnt/hdd/mynode/lnd/lnd.conf
fi

chown bitcoin:bitcoin /mnt/hdd/mynode/lnd/lnd.conf
