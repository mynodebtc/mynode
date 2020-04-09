#!/bin/bash

set -e
set -x 

source /usr/share/mynode/mynode_config.sh

# Verify FS is mounted as R/W
if [ ! -w / ]; then
    touch /tmp/sd_rw_error
    mount -o remount,rw /;
fi

# Set sticky bit on /tmp
chmod +t /tmp

# Make sure resolv.conf is a symlink to so resolvconf works
# if [ ! -h /etc/resolv.conf ]; then
#     rm -f /etc/resolv.conf
#     mkdir -p /etc/resolvconf/run/
#     touch /etc/resolvconf/run/resolv.conf
#     ln -s /etc/resolvconf/run/resolv.conf /etc/resolv.conf

#     sync
#     reboot
#     sleep 10s
#     exit 1
# fi

# Add some DNS servers to make domain lookup more likely
echo '' >> /etc/resolv.conf
echo '# Added at myNode startup' >> /etc/resolv.conf
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
echo 'nameserver 8.8.4.4' >> /etc/resolv.conf
echo 'nameserver 1.1.1.1' >> /etc/resolv.conf

# Disable autosuspend for USB drives
if [ -d /sys/bus/usb/devices/ ]; then 
    for dev in /sys/bus/usb/devices/*/power/control; do echo "on" > $dev; done 
fi

# Verify SD card permissions and folders are OK
mkdir -p /home/admin/.config/
chown -R admin:admin /home/admin/.config/


# Expand Root FS
mkdir -p /var/lib/mynode

if [ ! -f /var/lib/mynode/.expanded_rootfs ]; then
    if [ $IS_RASPI -eq 1 ]; then
        raspi-config --expand-rootfs
        touch /var/lib/mynode/.expanded_rootfs 
    fi
    if [ $IS_ROCK64 = 1 ] || [ $IS_ROCKPRO64 = 1 ]; then
        /usr/lib/armbian/armbian-resize-filesystem start
        touch /var/lib/mynode/.expanded_rootfs 
    fi
fi

# Verify we are in a clean state
if [ $IS_RASPI -eq 1 ] || [ $IS_ROCKPRO64 -eq 1 ]; then
    dphys-swapfile swapoff || true
    dphys-swapfile uninstall || true
fi
umount /mnt/hdd || true

# Check drive
set +e
if [ $IS_X86 = 0 ]; then
    touch /tmp/repairing_drive
    for d in /dev/sd*1; do
        echo "Repairing drive $d ...";
        fsck -y $d > /tmp/fsck_results 2>&1
        RC=$?
        if [ "$RC" -ne 0 ]; then
            touch /tmp/fsck_error
        fi
    done
fi
rm -f /tmp/repairing_drive
set -e


# Mount HDD (format if necessary)
while [ ! -f /mnt/hdd/.mynode ]
do
    # Clear status
    rm -f $MYNODE_DIR/.mynode_status
    mount_drive.tcl || true
    sleep 5
done


# Check for docker reset
if [ -f /home/bitcoin/reset_docker ]; then
    rm -rf /mnt/hdd/mynode/docker
    rm /home/bitcoin/reset_docker
    sync
    reboot
    sleep 60s
    exit 0
fi


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
mkdir -p /mnt/hdd/mynode/docker
mkdir -p /mnt/hdd/mynode/rtl_backup
mkdir -p /tmp/flask_uploads
echo "drive_mounted" > $MYNODE_DIR/.mynode_status
chmod 777 $MYNODE_DIR/.mynode_status
rm -rf $MYNODE_DIR/.mynode_bitcoind_synced


# Setup SD Card (if necessary)
mkdir -p /run/tor
mkdir -p /var/run/tor
mkdir -p /home/bitcoin/.mynode/
mkdir -p /home/admin/.bitcoin/
chown admin:admin /home/admin/.bitcoin/
rm -rf /etc/motd # Remove simple motd for update-motd.d

# Sync product key (SD preferred)
cp -f /home/bitcoin/.mynode/.product_key* /mnt/hdd/mynode/settings/ || true
cp -f /mnt/hdd/mynode/settings/.product_key* home/bitcoin/.mynode/ || true

# Make any users we need to
useradd -m -s /bin/bash pivpn || true

# Regen SSH keys (check if force regen or keys are missing / empty)
while [ ! -f /home/bitcoin/.mynode/.gensshkeys ] || 
      [ ! -f /etc/ssh/ssh_host_ecdsa_key.pub ] ||
      [ ! -s /etc/ssh/ssh_host_ecdsa_key.pub ] ||
      [ ! -f /etc/ssh/ssh_host_ed25519_key.pub ] ||
      [ ! -s /etc/ssh/ssh_host_ed25519_key.pub ] ||
      [ ! -f /etc/ssh/ssh_host_rsa_key.pub ] ||
      [ ! -s /etc/ssh/ssh_host_rsa_key.pub ]
do
    sleep 10s
    rm -rf /etc/ssh/ssh_host_*
    dpkg-reconfigure openssh-server
    systemctl restart ssh

    touch /home/bitcoin/.mynode/.gensshkeys
    sync
    sleep 5s
done

# Gen RSA keys
sudo -u admin mkdir -p /home/admin/.ssh
chown -R admin:admin /home/admin/.ssh
if [ ! -f /home/admin/.ssh/id_rsa ]; then
    sudo -u admin ssh-keygen -t rsa -f /home/admin/.ssh/id_rsa -N ""
fi
sudo -u admin touch /home/admin/.ssh/authorized_keys || true
if [ ! -f /root/.ssh/id_rsa_btcpay ]; then
    sudo rm -rf /root/.ssh/id_rsa_btcpay
    ssh-keygen -t rsa -f /root/.ssh/id_rsa_btcpay -q -P "" -m PEM
    echo "# Key used by BTCPay Server" >> /root/.ssh/authorized_keys
    cat /root/.ssh/id_rsa_btcpay.pub >> /root/.ssh/authorized_keys
fi

# Randomize RPC password
while [ ! -f /mnt/hdd/mynode/settings/.btcrpcpw ] || [ ! -s /mnt/hdd/mynode/settings/.btcrpcpw ]
do
    # Write random pw to .btcrpcpw
    sleep 10s
    < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-24} > /mnt/hdd/mynode/settings/.btcrpcpw
    chown bitcoin:bitcoin /mnt/hdd/mynode/settings/.btcrpcpw
    chmod 600 /mnt/hdd/mynode/settings/.btcrpcpw
done

# Setup LND Node Name
if [ ! -f /mnt/hdd/mynode/settings/.lndalias ]; then
    echo "mynodebtc.com [myNode]" > /mnt/hdd/mynode/settings/.lndalias
fi

# Default QuickSync
if [ ! -f /mnt/hdd/mynode/settings/.setquicksyncdefault ]; then
    # Default x86 to no QuickSync
    if [ $IS_X86 = 1 ]; then
        touch /mnt/hdd/mynode/settings/quicksync_disabled
    fi
    # Default RockPro64 to no QuickSync
    if [ $IS_ROCKPRO64 = 1 ]; then
        touch /mnt/hdd/mynode/settings/quicksync_disabled
    fi
    # Default SSD to no QuickSync
    DRIVE=$(cat /tmp/.mynode_drive)
    HDD=$(lsblk $DRIVE -o ROTA | tail -n 1 | tr -d '[:space:]')
    if [ "$HDD" = "0" ]; then
        touch /mnt/hdd/mynode/settings/quicksync_disabled
    fi
    # If there is a USB->SATA adapter, assume we have an SSD and default to no QS
    set +e
    lsusb | grep "SATA 6Gb/s bridge"
    RC=$?
    set -e
    if [ "$RC" = "0" ]; then
        touch /mnt/hdd/mynode/settings/quicksync_disabled
    fi
    # Default small drives to no QuickSync
    DRIVE_SIZE=$(df /mnt/hdd | grep /dev | awk '{print $2}')
    if (( ${DRIVE_SIZE} <= 800000000 )); then
        touch /mnt/hdd/mynode/settings/quicksync_disabled
    fi
    touch /mnt/hdd/mynode/settings/.setquicksyncdefault
fi


# BTC Config
source /usr/bin/mynode_gen_bitcoin_config.sh

# LND Config
source /usr/bin/mynode_gen_lnd_config.sh

# RTL config
sudo -u bitcoin mkdir -p /opt/mynode/RTL/
chown -R bitcoin:bitcoin /mnt/hdd/mynode/rtl_backup/
cp /usr/share/mynode/RTL-Config.json /opt/mynode/RTL/RTL-Config.json
if [ -f /home/bitcoin/.mynode/.hashedpw ]; then
    HASH=$(cat /home/bitcoin/.mynode/.hashedpw)
    sed -i "s/\"multiPassHashed\":.*/\"multiPassHashed\": \"$HASH\",/g" /opt/mynode/RTL/RTL-Config.json
fi
chown bitcoin:bitcoin /opt/mynode/RTL/RTL-Config.json

# BTC RPC Explorer Config
cp /usr/share/mynode/btc_rpc_explorer_env /opt/mynode/btc-rpc-explorer/.env
chown bitcoin:bitcoin /opt/mynode/btc-rpc-explorer/.env


# Update files that need RPC password (needed if upgrades overwrite files)
PW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
if [ -f /opt/mynode/LndHub/config.js ]; then
    cp -f /usr/share/mynode/lndhub-config.js /opt/mynode/LndHub/config.js
    sed -i "s/mynode:.*@/mynode:$PW@/g" /opt/mynode/LndHub/config.js
    chown bitcoin:bitcoin /opt/mynode/LndHub/config.js
fi
if [ -f /opt/mynode/btc-rpc-explorer/.env ]; then
    sed -i "s/BTCEXP_BITCOIND_PASS=.*/BTCEXP_BITCOIND_PASS=$PW/g" /opt/mynode/btc-rpc-explorer/.env
fi
echo "BTC_RPC_PASSWORD=$PW" > /mnt/hdd/mynode/settings/.btcrpc_environment
chown bitcoin:bitcoin /mnt/hdd/mynode/settings/.btcrpc_environment
if [ -f /mnt/hdd/mynode/bitcoin/bitcoin.conf ]; then
    #sed -i "s/rpcpassword=.*/rpcpassword=$PW/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
    sed -i "s/rpcauth=.*/$RPCAUTH/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
fi
cp -f /mnt/hdd/mynode/bitcoin/bitcoin.conf /home/admin/.bitcoin/bitcoin.conf
chown admin:admin /home/admin/.bitcoin/bitcoin.conf


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
if [ $IS_RASPI -eq 1 ] || [ $IS_ROCKPRO64 -eq 1 ]; then
    if [ ! -f /mnt/hdd/swapfile ]; then
        dd if=/dev/zero of=/mnt/hdd/swapfile count=1000 bs=1MiB
        chmod 600 /mnt/hdd/swapfile
    fi
    mkswap /mnt/hdd/swapfile
    dphys-swapfile swapon
fi


# Make sure every enabled service is really enabled
#   This can happen from full-SD card upgrades
STARTUP_MODIFIED=0
if [ -f $ELECTRS_ENABLED_FILE ]; then
    if systemctl status electrs | grep "disabled;"; then
        systemctl enable electrs
        STARTUP_MODIFIED=1
    fi
fi
if [ -f $LNDHUB_ENABLED_FILE ]; then
    if systemctl status lndhub | grep "disabled;"; then
        systemctl enable lndhub
        STARTUP_MODIFIED=1
    fi
fi
if [ -f $BTCRPCEXPLORER_ENABLED_FILE ]; then
    if systemctl status btc_rpc_explorer | grep "disabled;"; then
        systemctl enable btc_rpc_explorer
        STARTUP_MODIFIED=1
    fi
fi
if [ -f $MEMPOOLSPACE_ENABLED_FILE ]; then
    if systemctl status mempoolspace | grep "disabled;"; then
        systemctl enable mempoolspace
        STARTUP_MODIFIED=1
    fi
fi
if [ -f $BTCPAYSERVER_ENABLED_FILE ]; then
    if systemctl status btcpayserver | grep "disabled;"; then
        systemctl enable btcpayserver
        STARTUP_MODIFIED=1
    fi
fi
if [ -f $VPN_ENABLED_FILE ]; then
    if systemctl status vpn | grep "disabled;"; then
        systemctl enable vpn
        systemctl enable openvpn || true
        STARTUP_MODIFIED=1
    fi
fi
if [ $STARTUP_MODIFIED -eq 1 ]; then
    sync
    reboot
    exit 0
fi


# Weird hacks
chmod +x /usr/bin/electrs || true # Once, a device didn't have the execute bit set for electrs
timedatectl set-ntp True || true # Make sure NTP is enabled for Tor and Bitcoin

# Check for new versions
wget $LATEST_VERSION_URL -O /usr/share/mynode/latest_version || true
wget $LATEST_BETA_VERSION_URL -O /usr/share/mynode/latest_beta_version || true

# Update current state
if [ -f $QUICKSYNC_DIR/.quicksync_complete ]; then
    echo "stable" > $MYNODE_DIR/.mynode_status
fi
