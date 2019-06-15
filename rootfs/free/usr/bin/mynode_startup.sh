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
if [ $IS_RASPI -eq 1 ]; then
    if [ ! -f /var/lib/mynode/.expanded_rootfs ]; then
        raspi-config --expand-rootfs
        touch /var/lib/mynode/.expanded_rootfs 
    fi
fi

# Verify we are in a clean state (only raspi uses HDD swap)
if [ $IS_RASPI -eq 1 ]; then
    dphys-swapfile swapoff || true
    dphys-swapfile uninstall || true
fi
umount /mnt/hdd || true


# Mount HDD (format if necessary)
while [ ! -f /mnt/hdd/.mynode ]
do
    mount_drive.tcl || true
    sleep 10
done

# Setup Drive
mkdir -p /mnt/hdd/mynode
mkdir -p /mnt/hdd/mynode/bitcoin
mkdir -p /mnt/hdd/mynode/lnd
mkdir -p /mnt/hdd/mynode/quicksync
echo "drive_mounted" > $MYNODE_DIR/.mynode_status
chmod 777 $MYNODE_DIR/.mynode_status
rm -rf $MYNODE_DIR/.mynode_bitcoind_synced


# Setup SD Card (if necessary)
mkdir -p /home/admin/.bitcoin/
chown admin:admin /home/admin/.bitcoin/


# Regen SSH keys
mkdir -p /home/bitcoin/.mynode/
if [ ! -f /home/bitcoin/.mynode/.gensshkeys ]; then
    rm -rf /etc/ssh/ssh_host_*
    dpkg-reconfigure openssh-server
    systemctl restart ssh

    touch /home/bitcoin/.mynode/.gensshkeys
fi


# Randomize RPC password
mkdir -p /home/bitcoin/.mynode/
if [ ! -f /home/bitcoin/.mynode/.btcrpcpw ]; then
    # Write random pw to .btcrpcpw
    < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-24} > /home/bitcoin/.mynode/.btcrpcpw
    chown bitcoin:bitcoin /home/bitcoin/.mynode/.btcrpcpw
    chmod 600 /home/bitcoin/.mynode/.btcrpcpw
fi


# Copy config files from /usr/share to /mnt/hdd if necessary
if [ ! -f /mnt/hdd/mynode/bitcoin/bitcoin.conf ]; then
    cp -f /usr/share/mynode/bitcoin.conf /mnt/hdd/mynode/bitcoin/bitcoin.conf
    
    PW=$(cat /home/bitcoin/.mynode/.btcrpcpw)
    sed -i "s/rpcpassword=.*/rpcpassword=$PW/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    
    cp -f /mnt/hdd/mynode/bitcoin/bitcoin.conf /home/admin/.bitcoin/bitcoin.conf
    chown bitcoin:bitcoin /mnt/hdd/mynode/bitcoin/bitcoin.conf
    chown admin:admin /home/admin/.bitcoin/bitcoin.conf
fi
if [ ! -f /mnt/hdd/mynode/lnd/lnd.conf ]; then
    cp /usr/share/mynode/lnd.conf /mnt/hdd/mynode/lnd/lnd.conf
    chown bitcoin:bitcoin /mnt/hdd/mynode/lnd/lnd.conf
fi

# Update files that need RPC password (needed if upgrades overwrite files)
PW=$(cat /home/bitcoin/.mynode/.btcrpcpw)
echo "BTC_RPC_PASSWORD=$PW" > /home/bitcoin/.mynode/.btcrpc_environment
chown bitcoin:bitcoin /home/bitcoin/.mynode/.btcrpc_environment
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


# Update current state
if [ -f $QUICKSYNC_DIR/.quicksync_complete ]; then
    echo "stable" > $MYNODE_DIR/.mynode_status
fi
