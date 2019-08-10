#!/bin/bash

set -e
set -x 

source /usr/share/mynode/mynode_config.sh

# Verify FS is mounted as R/W
if [ ! -w / ]; then
    mount -o remount,rw /;
fi

# Expand Root FS
mkdir -p /var/lib/mynode

if [ ! -f /var/lib/mynode/.expanded_rootfs ]; then
    if [ $IS_RASPI -eq 1 ]; then
        raspi-config --expand-rootfs
        touch /var/lib/mynode/.expanded_rootfs 
    fi
    if [ $IS_ROCK64 = 1 ]; then
        /usr/lib/armbian/armbian-resize-filesystem start
        touch /var/lib/mynode/.expanded_rootfs 
    fi
fi

# Verify we are in a clean state (only raspi uses HDD swap)
if [ $IS_RASPI -eq 1 ]; then
    dphys-swapfile swapoff || true
    dphys-swapfile uninstall || true
fi
umount /mnt/hdd || true

# Check for drive-repair
if [ -f /home/bitcoin/.mynode/check_drive ]; then
    for d in /dev/sd*1; do
        echo "Repairing drive $d ...";
        fsck -y $d
    done
    rm /home/bitcoin/.mynode/check_drive
fi

# Mount HDD (format if necessary)
while [ ! -f /mnt/hdd/.mynode ]
do
    mount_drive.tcl || true
    sleep 10
done

# Setup Drive
mkdir -p /mnt/hdd/mynode
mkdir -p /mnt/hdd/mynode/settings
mkdir -p /mnt/hdd/mynode/.config
mkdir -p /mnt/hdd/mynode/bitcoin
mkdir -p /mnt/hdd/mynode/lnd
mkdir -p /mnt/hdd/mynode/quicksync
mkdir -p /mnt/hdd/mynode/redis
mkdir -p /mnt/hdd/mynode/mongodb
mkdir -p /mnt/hdd/mynode/electrs
echo "drive_mounted" > $MYNODE_DIR/.mynode_status
chmod 777 $MYNODE_DIR/.mynode_status
rm -rf $MYNODE_DIR/.mynode_bitcoind_synced


# Setup SD Card (if necessary)
mkdir -p /home/bitcoin/.mynode/
mkdir -p /home/admin/.bitcoin/
chown admin:admin /home/admin/.bitcoin/
rm -rf /etc/motd # Remove simple motd for update-motd.d

# Make any users we need to
useradd -m -s /bin/bash pivpn || true

# Regen SSH keys
if [ ! -f /home/bitcoin/.mynode/.gensshkeys ]; then
    rm -rf /etc/ssh/ssh_host_*
    dpkg-reconfigure openssh-server
    systemctl restart ssh

    touch /home/bitcoin/.mynode/.gensshkeys
fi

# Sync product key (SD preferred)
cp -f /home/bitcoin/.mynode/.product_key* /mnt/hdd/mynode/settings/ || true
cp -f /mnt/hdd/mynode/settings/.product_key* home/bitcoin/.mynode/ || true

# Randomize RPC password
if [ ! -f /mnt/hdd/mynode/settings/.btcrpcpw ]; then
    # Write random pw to .btcrpcpw
    < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-24} > /mnt/hdd/mynode/settings/.btcrpcpw
    chown bitcoin:bitcoin /mnt/hdd/mynode/settings/.btcrpcpw
    chmod 600 /mnt/hdd/mynode/settings/.btcrpcpw
fi

# Setup LND Node Name
if [ ! -f /mnt/hdd/mynode/settings/.lndalias ]; then
    echo "mynodebtc.com [myNode]" > /mnt/hdd/mynode/settings/.lndalias
fi


# BTC Config
cp -f /usr/share/mynode/bitcoin.conf /mnt/hdd/mynode/bitcoin/bitcoin.conf

PW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
sed -i "s/rpcpassword=.*/rpcpassword=$PW/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf

cp -f /mnt/hdd/mynode/bitcoin/bitcoin.conf /home/admin/.bitcoin/bitcoin.conf
chown bitcoin:bitcoin /mnt/hdd/mynode/bitcoin/bitcoin.conf
chown admin:admin /home/admin/.bitcoin/bitcoin.conf

# LND Config
cp /usr/share/mynode/lnd.conf /mnt/hdd/mynode/lnd/lnd.conf
ALIAS=$(cat /mnt/hdd/mynode/settings/.lndalias)
sed -i "s/alias=.*/alias=$ALIAS/g" /mnt/hdd/mynode/lnd/lnd.conf
chown bitcoin:bitcoin /mnt/hdd/mynode/lnd/lnd.conf

# RTL config
cp /usr/share/mynode/RTL.conf /opt/mynode/RTL/RTL.conf
if [ -f /home/bitcoin/.mynode/.hashedpw ]; then
    HASH=$(cat /home/bitcoin/.mynode/.hashedpw)
    sed -i "s/rtlPassHashed=.*/rtlPassHashed=$HASH/g" /opt/mynode/RTL/RTL.conf
fi
chown bitcoin:bitcoin /opt/mynode/RTL/RTL.conf


# Update files that need RPC password (needed if upgrades overwrite files)
PW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
if [ -f /opt/mynode/LndHub/config.js ]; then
    sed -i "s/mynode:.*@/mynode:$PW@/g" /opt/mynode/LndHub/config.js
fi
if [ -f /opt/mynode/btc-rpc-explorer/.env ]; then
    sed -i "s/BTCEXP_BITCOIND_PASS=.*/BTCEXP_BITCOIND_PASS=$PW/g" /opt/mynode/btc-rpc-explorer/.env
fi
echo "BTC_RPC_PASSWORD=$PW" > /mnt/hdd/mynode/settings/.btcrpc_environment
chown bitcoin:bitcoin /mnt/hdd/mynode/settings/.btcrpc_environment
if [ -f /mnt/hdd/mynode/bitcoin/bitcoin.conf ]; then
    sed -i "s/rpcpassword=.*/rpcpassword=$PW/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
fi
if [ -f /home/admin/.bitcoin/bitcoin.conf ]; then
    sed -i "s/rpcpassword=.*/rpcpassword=$PW/g" /home/admin/.bitcoin/bitcoin.conf
else
    cp -f /mnt/hdd/mynode/bitcoin/bitcoin.conf /home/admin/.bitcoin/bitcoin.conf
    chown admin:admin /home/admin/.bitcoin/bitcoin.conf
fi

# Reset BTCARGS
echo "BTCARGS=" > /mnt/hdd/mynode/bitcoin/env


# Set proper permissions on drive
USER=$(stat -c '%U' /mnt/hdd/mynode/quicksync)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/quicksync
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/settings)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/settings
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/.config)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/.config
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/bitcoin)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/bitcoin
fi
USER=$(stat -c '%U' /home/bitcoin)
if [ "$USER" != "bitcoin" ]; then
    chown -R --no-dereference bitcoin:bitcoin /home/bitcoin
fi
USER=$(stat -c '%U' /home/bitcoin/.mynode)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/lnd)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/lnd
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/redis)
if [ "$USER" != "redis" ]; then
    chown -R redis:redis /mnt/hdd/mynode/redis
fi
chown -R redis:redis /etc/redis/
#USER=$(stat -c '%U' /mnt/hdd/mynode/mongodb)
#if [ "$USER" != "mongodb" ]; then
#    chown -R mongodb:mongodb /mnt/hdd/mynode/mongodb
#fi
USER=$(stat -c '%U' /mnt/hdd/mynode/electrs)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/electrs
fi
chown bitcoin:bitcoin /mnt/hdd/
chown bitcoin:bitcoin /mnt/hdd/mynode/


# Setup swap on new HDD
if [ $IS_RASPI -eq 1 ]; then
    if [ ! -f /mnt/hdd/swapfile ]; then
        dd if=/dev/zero of=/mnt/hdd/swapfile count=1000 bs=1MiB
        chmod 600 /mnt/hdd/swapfile
    fi
    mkswap /mnt/hdd/swapfile
    dphys-swapfile setup
    dphys-swapfile swapon
fi

# Add some DNS servers to make domain lookup more likely
echo '' >> /etc/resolv.conf
echo '# Added at myNode startup' >> /etc/resolv.conf
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
echo 'nameserver 8.8.4.4' >> /etc/resolv.conf
echo 'nameserver 1.1.1.1' >> /etc/resolv.conf

# Check for new versions
wget $LATEST_VERSION_URL -O /usr/share/mynode/latest_version || true

# Update current state
if [ -f $QUICKSYNC_DIR/.quicksync_complete ]; then
    echo "stable" > $MYNODE_DIR/.mynode_status
fi
