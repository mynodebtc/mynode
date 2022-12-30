#!/bin/bash

TOTAL_RAM_GB=$(free --giga | grep Mem | awk '{print $2}')

# Setup default settings (new - 2022)
if [ ! -f /mnt/hdd/mynode/settings/btc_network_settings_defaulted ] && [ ! -f /home/bitcoin/.mynode/btc_network_settings_defaulted ]; then

    # based on old settings, set ipv4 or tor
    if [ -f /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled_defaulted ] || [ -f /home/bitcoin/.mynode/.btc_lnd_tor_enabled_defaulted ]; then
        if [ -f /home/bitcoin/.mynode/btc_lnd_tor_enabled ] || [ -f /mnt/hdd/mynode/settings/btc_lnd_tor_enabled ]; then
            # Old settings indicate tor
            touch /home/bitcoin/.mynode/btc_tor_enabled
            touch /mnt/hdd/mynode/settings/btc_tor_enabled
        else
            # Old settings indicate ipv4
            touch /home/bitcoin/.mynode/btc_ipv4_enabled
            touch /mnt/hdd/mynode/settings/btc_ipv4_enabled
        fi
    else
        # Set new defaults
        touch /home/bitcoin/.mynode/btc_tor_enabled
        touch /mnt/hdd/mynode/settings/btc_tor_enabled
        touch /home/bitcoin/.mynode/btc_i2p_enabled
        touch /mnt/hdd/mynode/settings/btc_i2p_enabled
    fi

    touch /mnt/hdd/mynode/settings/btc_network_settings_defaulted
    touch /home/bitcoin/.mynode/btc_network_settings_defaulted
    sync
fi


# Generate BTC Config
if [ -f /mnt/hdd/mynode/settings/bitcoin_custom.conf ]; then
    # Use Custom Config
    cp -f /mnt/hdd/mynode/settings/bitcoin_custom.conf /mnt/hdd/mynode/bitcoin/bitcoin.conf
else
    # Generate a default config
    cp -f /usr/share/mynode/bitcoin.conf /mnt/hdd/mynode/bitcoin/bitcoin.conf
    sync

    # Generate config based on RAM
    if [ "$TOTAL_RAM_GB" -le "1"  ]; then
        sed -i "s/dbcache=.*/dbcache=225/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=50/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    elif [ "$TOTAL_RAM_GB" -le "2" ]; then
        sed -i "s/dbcache=.*/dbcache=500/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=100/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    elif [ "$TOTAL_RAM_GB" -le "3" ]; then
        sed -i "s/dbcache=.*/dbcache=700/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=150/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    elif [ "$TOTAL_RAM_GB" -le "4" ]; then
        sed -i "s/dbcache=.*/dbcache=1000/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=250/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    elif [ "$TOTAL_RAM_GB" -le "6" ]; then
        sed -i "s/dbcache=.*/dbcache=2000/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=400/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    elif [ "$TOTAL_RAM_GB" -le "8" ]; then
        sed -i "s/dbcache=.*/dbcache=3000/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=500/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    elif [ "$TOTAL_RAM_GB" -le "12" ]; then
        sed -i "s/dbcache=.*/dbcache=4000/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=800/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    elif [ "$TOTAL_RAM_GB" -le "16" ]; then
        sed -i "s/dbcache=.*/dbcache=5000/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=1000/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    elif [ "$TOTAL_RAM_GB" -le "32" ]; then
        sed -i "s/dbcache=.*/dbcache=8000/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=1500/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    elif [ "$TOTAL_RAM_GB" -le "64" ]; then
        sed -i "s/dbcache=.*/dbcache=12000/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=2000/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    else
        echo "UNKNOWN RAM AMMOUNT: $TOTAL_RAM_GB"
        sed -i "s/dbcache=.*/dbcache=500/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=50/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi

    # Append network sections (IPv4 / Tor / I2P)
    if [ -f /mnt/hdd/mynode/settings/btc_ipv4_enabled ] || [ -f /home/bitcoin/.mynode/btc_ipv4_enabled ]; then
        cat /usr/share/mynode/bitcoin_ipv4.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    else
        cat /usr/share/mynode/bitcoin_no_ipv4.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi
    if [ -f /mnt/hdd/mynode/settings/btc_tor_enabled ] || [ -f /home/bitcoin/.mynode/btc_tor_enabled ]; then
        cat /usr/share/mynode/bitcoin_tor.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi
    if [ -f /mnt/hdd/mynode/settings/btc_i2p_enabled ] || [ -f /home/bitcoin/.mynode/btc_i2p_enabled ]; then
        cat /usr/share/mynode/bitcoin_i2p.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi

    # Append Mainnet/Testnet section
    if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
        cat /usr/share/mynode/bitcoin_testnet.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi

    # Append BIP setting toggles
    if [ -f /mnt/hdd/mynode/settings/.bip37_enabled ]; then
        cat /usr/share/mynode/bitcoin_bip37.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi
    if [ -f /mnt/hdd/mynode/settings/.bip157_enabled ]; then
        cat /usr/share/mynode/bitcoin_bip157.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi
    if [ -f /mnt/hdd/mynode/settings/.bip158_enabled ]; then
        cat /usr/share/mynode/bitcoin_bip158.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi

    # Update Debug Log Settings
    if [ -f /home/bitcoin/.mynode/keep_bitcoin_debug_log ] || [ -f /mnt/hdd/mynode/settings/keep_bitcoin_debug_log ]; then
        sed -i "s/shrinkdebugfile=.*/shrinkdebugfile=0/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi

    # Append "extra" config
    if [ -f /mnt/hdd/mynode/settings/bitcoin_extra_config.conf ]; then
        echo "" >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
        echo "# Extra BTC Config" >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
        echo "" >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
        cat /mnt/hdd/mynode/settings/bitcoin_extra_config.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
        echo "" >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi
fi

PW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
RPCAUTH=$(gen_rpcauth.py mynode $PW)
#sed -i "s/rpcpassword=.*/rpcpassword=$PW/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
sed -i "s/rpcauth=.*/$RPCAUTH/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf

chown bitcoin:bitcoin /mnt/hdd/mynode/bitcoin/bitcoin.conf
