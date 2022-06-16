#!/bin/bash

TOTAL_RAM_GB=$(free --giga | grep Mem | awk '{print $2}')

# Setup default settings
if [ ! -f /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled_defaulted ] && [ ! -f /home/bitcoin/.mynode/.btc_lnd_tor_enabled_defaulted ]; then
    touch /home/bitcoin/.mynode/.btc_lnd_tor_enabled_defaulted
    touch /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled_defaulted
    touch /home/bitcoin/.mynode/btc_lnd_tor_enabled
    touch /mnt/hdd/mynode/settings/btc_lnd_tor_enabled
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
        sed -i "s/dbcache=.*/dbcache=2500/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=500/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    elif [ "$TOTAL_RAM_GB" -le "12" ]; then
        sed -i "s/dbcache=.*/dbcache=4000/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=800/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    elif [ "$TOTAL_RAM_GB" -le "16" ]; then
        sed -i "s/dbcache=.*/dbcache=5000/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=800/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    else
        echo "UNKNOWN RAM AMMOUNT: $TOTAL_RAM_GB"
        sed -i "s/dbcache=.*/dbcache=500/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
        sed -i "s/maxmempool=.*/maxmempool=50/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    fi

    # Append Tor/IP section (check new file or old file, should be migrated to new)
    if [ -f /mnt/hdd/mynode/settings/btc_lnd_tor_enabled ] || [ -f /home/bitcoin/.mynode/btc_lnd_tor_enabled ]; then
        cat /usr/share/mynode/bitcoin_tor.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
    else
        cat /usr/share/mynode/bitcoin_ipv4.conf >> /mnt/hdd/mynode/bitcoin/bitcoin.conf
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
fi

PW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
RPCAUTH=$(gen_rpcauth.py mynode $PW)
#sed -i "s/rpcpassword=.*/rpcpassword=$PW/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
sed -i "s/rpcauth=.*/$RPCAUTH/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf

chown bitcoin:bitcoin /mnt/hdd/mynode/bitcoin/bitcoin.conf
