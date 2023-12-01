#!/bin/bash

# Setup default settings (new - 2022)
if [ ! -f /mnt/hdd/mynode/settings/lnd_network_settings_defaulted ] && [ ! -f /home/bitcoin/.mynode/lnd_network_settings_defaulted ]; then

    # based on old settings, set ipv4 or tor
    if [ -f /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled_defaulted ] || [ -f /home/bitcoin/.mynode/.btc_lnd_tor_enabled_defaulted ]; then
        if [ -f /home/bitcoin/.mynode/btc_lnd_tor_enabled ] || [ -f /mnt/hdd/mynode/settings/btc_lnd_tor_enabled ]; then
            # Old settings indicate tor only
            touch /home/bitcoin/.mynode/lnd_tor_enabled
            touch /mnt/hdd/mynode/settings/lnd_tor_enabled
        else
            # Old settings indicate ipv4 only
            touch /home/bitcoin/.mynode/lnd_ipv4_enabled
            touch /mnt/hdd/mynode/settings/lnd_ipv4_enabled
        fi
    else
        # Set new defaults
        touch /home/bitcoin/.mynode/lnd_tor_enabled
        touch /mnt/hdd/mynode/settings/lnd_tor_enabled
    fi

    touch /mnt/hdd/mynode/settings/lnd_network_settings_defaulted
    touch /home/bitcoin/.mynode/lnd_network_settings_defaulted
    sync
fi

# Setup Initial LND Node Name
if [ ! -f /mnt/hdd/mynode/settings/.lndalias ]; then
    echo "mynodebtc.com [MyNode]" > /mnt/hdd/mynode/settings/.lndalias
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

    IPV4_ENABLED=0
    if [ -f /mnt/hdd/mynode/settings/lnd_ipv4_enabled ] || [ -f /home/bitcoin/.mynode/lnd_ipv4_enabled ]; then
        IPV4_ENABLED=1
    fi
    TOR_ENABLED=0
    if [ -f /mnt/hdd/mynode/settings/lnd_tor_enabled ] || [ -f /home/bitcoin/.mynode/lnd_tor_enabled ]; then
        TOR_ENABLED=1
    fi

    # Append Network Config (IPv4 / Tor)
    if [ $IPV4_ENABLED = 1 ]; then
        cat /usr/share/mynode/lnd_ipv4.conf >> /mnt/hdd/mynode/lnd/lnd.conf
    else
        cat /usr/share/mynode/lnd_no_ipv4.conf >> /mnt/hdd/mynode/lnd/lnd.conf
    fi
    if [ $TOR_ENABLED = 1 ]; then
        cat /usr/share/mynode/lnd_tor.conf >> /mnt/hdd/mynode/lnd/lnd.conf
    else
        cat /usr/share/mynode/lnd_no_tor.conf >> /mnt/hdd/mynode/lnd/lnd.conf
    fi


    # Update LND Tor stream isolation (true is default) (also disabled if hybrid mode)
    if [ -f /mnt/hdd/mynode/settings/streamisolation_tor_disabled ]; then
        sed -i "s/tor.streamisolation=.*/tor.streamisolation=false/g" /mnt/hdd/mynode/lnd/lnd.conf || true
    fi
    if [ $IPV4_ENABLED = 1 ] && [ $TOR_ENABLED = 1 ]; then
        sed -i "s/tor.streamisolation=.*/tor.streamisolation=false/g" /mnt/hdd/mynode/lnd/lnd.conf || true
    fi

    # Append Mainnet/Testnet section
    if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
        sed -i "s/bitcoin.mainnet=.*/bitcoin.mainnet=0/g" /mnt/hdd/mynode/lnd/lnd.conf
        sed -i "s/bitcoin.testnet=.*/bitcoin.testnet=1/g" /mnt/hdd/mynode/lnd/lnd.conf
        cat /usr/share/mynode/lnd_testnet.conf >> /mnt/hdd/mynode/lnd/lnd.conf
    fi

    # Append "extra" config
    if [ -f /mnt/hdd/mynode/settings/lnd_extra_config.conf ]; then
        echo "" >> /mnt/hdd/mynode/lnd/lnd.conf
        echo "# Extra LND Config" >> /mnt/hdd/mynode/lnd/lnd.conf
        echo "[Application Options]" >> /mnt/hdd/mynode/lnd/lnd.conf
        echo "" >> /mnt/hdd/mynode/lnd/lnd.conf
        cat /mnt/hdd/mynode/settings/lnd_extra_config.conf >> /mnt/hdd/mynode/lnd/lnd.conf
        echo "" >> /mnt/hdd/mynode/lnd/lnd.conf
    fi
fi

# Append tor domain
if [ -f /var/lib/tor/mynode_lnd/hostname ]; then
    echo "" >> /mnt/hdd/mynode/lnd/lnd.conf
    echo "[Application Options]" >> /mnt/hdd/mynode/lnd/lnd.conf
    ONION_URL=$(cat /var/lib/tor/mynode_lnd/hostname)
    echo "tlsextradomain=$ONION_URL" >> /mnt/hdd/mynode/lnd/lnd.conf
    echo "tlsextradomain=host.docker.internal" >> /mnt/hdd/mynode/lnd/lnd.conf
    echo "" >> /mnt/hdd/mynode/lnd/lnd.conf
fi

# Set Alias
ALIAS=$(cat /mnt/hdd/mynode/settings/.lndalias)
sed -i "s/alias=.*/alias=$ALIAS/g" /mnt/hdd/mynode/lnd/lnd.conf
chown bitcoin:bitcoin /mnt/hdd/mynode/lnd/lnd.conf