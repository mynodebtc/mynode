#!/bin/bash

set -e
set -x 
shopt -s nullglob

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_app_versions.sh

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
needDns=0
grep "Added at myNode startup" /etc/resolv.conf || needDns=1
if [ $needDns = 1 ]; then
    echo '' >> /etc/resolv.conf
    echo '# Added at myNode startup' >> /etc/resolv.conf
    echo 'nameserver 1.1.1.1' >> /etc/resolv.conf
    echo 'nameserver 208.67.222.222' >> /etc/resolv.conf
    echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
    echo 'nameserver 8.8.4.4' >> /etc/resolv.conf
fi

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


# Setup SD Card (if necessary)
mkdir -p /run/tor
mkdir -p /var/run/tor
mkdir -p /home/bitcoin/.mynode/
mkdir -p /home/admin/.bitcoin/
chown admin:admin /home/admin/.bitcoin/
rm -rf /etc/motd # Remove simple motd for update-motd.d


# Customize logo for resellers
if [ -f /opt/mynode/custom/logo_custom.png ]; then
    cp -f /opt/mynode/custom/logo_custom.png /var/www/mynode/static/images/logo_custom.png 
fi
if [ -f /opt/mynode/custom/logo_dark_custom.png ]; then
    cp -f /opt/mynode/custom/logo_dark_custom.png /var/www/mynode/static/images/logo_dark_custom.png
fi


# Verify we are in a clean state
if [ $IS_X86 = 1 ]; then
    swapoff -a || true
fi
dphys-swapfile swapoff || true
dphys-swapfile uninstall || true
umount /mnt/hdd || true


# Generate myNode serial number
while [ ! -f /home/bitcoin/.mynode/mynode_serial ] || [ ! -s /home/bitcoin/.mynode/mynode_serial ]
do
    # Generate random serial for backup devices that don't have serial numbers
    sleep 10s
    < /dev/urandom tr -dc a-f0-9 | head -c${1:-16} > /home/bitcoin/.mynode/mynode_serial
    chmod 644 /home/bitcoin/.mynode/mynode_serial
done


# Clone tool was opened
if [ -f /home/bitcoin/open_clone_tool ]; then
    rm -f /home/bitcoin/open_clone_tool
    echo "drive_clone" > $MYNODE_STATUS_FILE
    sync
    while [ 1 ]; do
        python3 /usr/bin/clone_drive.py || true
        sleep 60s
    done
fi


# Check drive (only if exactly 1 is found)
set +e
if [ $IS_X86 = 0 ]; then
    touch /tmp/repairing_drive
    for d in /dev/sd*1 /dev/hd*1 /dev/vd*1 /dev/nvme*p1; do
        echo "Repairing drive $d ...";
        fsck -y $d > /tmp/fsck_results 2>&1
        RC=$?
        echo "" >> /tmp/fsck_results
        echo "Code: $RC" >> /tmp/fsck_results
        if [ "$RC" -ne 0 ] && [ "$RC" -ne 8 ] ; then
            touch /tmp/fsck_error
        fi
    done
fi
rm -f /tmp/repairing_drive
set -e


# Mount HDD (normal boot, format if necessary)
while [ ! -f /mnt/hdd/.mynode ]
do
    # Normal boot - find drive 
    rm -f $MYNODE_STATUS_FILE # Clear status
    mount_drive.tcl || true
    sleep 5s
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


# Check drive usage
mb_available=$(df --block-size=M /mnt/hdd | grep /dev | awk '{print $4}' | cut -d'M' -f1)
if [ $mb_available -le 1200 ]; then
    echo "drive_full" > $MYNODE_STATUS_FILE
    sleep 10s
    mb_available=$(df --block-size=M /mnt/hdd | grep /dev | awk '{print $4}' | cut -d'M' -f1)
fi


# Setup Drive
mkdir -p /mnt/hdd/mynode
mkdir -p /mnt/hdd/mynode/settings
mkdir -p /mnt/hdd/mynode/.config
mkdir -p /mnt/hdd/mynode/bitcoin
mkdir -p /mnt/hdd/mynode/lnd
mkdir -p /mnt/hdd/mynode/loop
mkdir -p /mnt/hdd/mynode/pool
mkdir -p /mnt/hdd/mynode/faraday
mkdir -p /mnt/hdd/mynode/lit
mkdir -p /mnt/hdd/mynode/quicksync
mkdir -p /mnt/hdd/mynode/redis
mkdir -p /mnt/hdd/mynode/mongodb
mkdir -p /mnt/hdd/mynode/electrs
mkdir -p /mnt/hdd/mynode/docker
mkdir -p /mnt/hdd/mynode/rtl
mkdir -p /mnt/hdd/mynode/rtl_backup
mkdir -p /mnt/hdd/mynode/whirlpool
mkdir -p /mnt/hdd/mynode/lnbits
mkdir -p /mnt/hdd/mynode/specter
mkdir -p /mnt/hdd/mynode/ckbunker
mkdir -p /mnt/hdd/mynode/sphinxrelay
mkdir -p /mnt/hdd/mynode/joinmarket
mkdir -p /mnt/hdd/mynode/mempool
mkdir -p /mnt/hdd/mynode/tor_backup
mkdir -p /tmp/flask_uploads
echo "drive_mounted" > $MYNODE_STATUS_FILE
chmod 777 $MYNODE_STATUS_FILE
rm -rf $MYNODE_DIR/.mynode_bitcoind_synced


# Sync product key (SD preferred)
cp -f /home/bitcoin/.mynode/.product_key* /mnt/hdd/mynode/settings/ || true
cp -f /mnt/hdd/mynode/settings/.product_key* home/bitcoin/.mynode/ || true

# Make any users we need to
useradd -m -s /bin/bash pivpn || true
useradd -m -s /bin/bash joinmarket || true

# User updates and settings
adduser admin bitcoin
grep "joinmarket" /etc/sudoers || (echo 'joinmarket ALL=(ALL) NOPASSWD:ALL' | EDITOR='tee -a' visudo)

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

# Loop Config
source /usr/bin/mynode_gen_loop_config.sh

# Pool Config
source /usr/bin/mynode_gen_pool_config.sh

# Lightning Terminal Config
source /usr/bin/mynode_gen_lit_config.sh

# Setup symlinks for bitcoin user so they have access to commands
users="bitcoin"
services="bitcoin lnd lit loop pool faraday"
for u in $users; do
    for s in $services; do
        if [ ! -L /home/$u/.$s ]; then
            if [ -d /home/$u/.$s ]; then
                mv /home/$u/.$s /home/$u/.${s}_backup || true # Backup just in case
            fi
            sudo -u $u ln -s /mnt/hdd/mynode/$s /home/$u/.$s
        fi
    done
done

# Setup symlinks for admin (need to be careful here - lnd,bitcoin can't be symlinked)
if [ ! -L /home/admin/.pool ]; then     # Pool Config (symlink so admin user can run pool commands)
    mv /home/admin/.pool /home/admin/.pool_backup || true
    ln -s /mnt/hdd/mynode/pool /home/admin/.pool
fi
if [ ! -L /home/admin/.loop ]; then     # Loop Config (symlink so admin user can run loop commands)
    mv /home/admin/.loop /home/admin/.loop_backup || true
    ln -s /mnt/hdd/mynode/loop /home/admin/.loop
fi


# Dojo - move to HDD
if [ -d /opt/mynode/dojo ] && [ ! -d /mnt/hdd/mynode/dojo ] ; then
    mv /opt/mynode/dojo /mnt/hdd/mynode/dojo
fi


# Setup electrs
cp -f /usr/share/mynode/electrs.toml /mnt/hdd/mynode/electrs/electrs.toml
# Update for testnet
if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
    sed -i "s/bitcoin/testnet/g" /mnt/hdd/mynode/electrs/electrs.toml || true
else
    sed -i "s/testnet/bitcoin/g" /mnt/hdd/mynode/electrs/electrs.toml || true
fi

# RTL config
sudo -u bitcoin mkdir -p /opt/mynode/RTL
sudo -u bitcoin mkdir -p /mnt/hdd/mynode/rtl
chown -R bitcoin:bitcoin /mnt/hdd/mynode/rtl
chown -R bitcoin:bitcoin /mnt/hdd/mynode/rtl_backup
# If local settings file is not a symlink, delete and setup symlink to HDD
if [ ! -L /opt/mynode/RTL/RTL-Config.json ]; then
    rm -f /opt/mynode/RTL/RTL-Config.json
    sudo -u bitcoin ln -s /mnt/hdd/mynode/rtl/RTL-Config.json /opt/mynode/RTL/RTL-Config.json
fi
# If config file on HDD does not exist, create it
if [ ! -f /mnt/hdd/mynode/rtl/RTL-Config.json ]; then
    cp -f /usr/share/mynode/RTL-Config.json /mnt/hdd/mynode/rtl/RTL-Config.json
fi
# Force update of RTL config file (increment to force new update)
RTL_CONFIG_UPDATE_NUM=1
if [ ! -f /mnt/hdd/mynode/rtl/update_settings_$RTL_CONFIG_UPDATE_NUM ]; then
    cp -f /usr/share/mynode/RTL-Config.json /mnt/hdd/mynode/rtl/RTL-Config.json
    touch /mnt/hdd/mynode/rtl/update_settings_$RTL_CONFIG_UPDATE_NUM
fi
# Update RTL config file to use mynode pw
if [ -f /home/bitcoin/.mynode/.hashedpw ]; then
    HASH=$(cat /home/bitcoin/.mynode/.hashedpw)
    sed -i "s/\"multiPassHashed\":.*/\"multiPassHashed\": \"$HASH\",/g" /mnt/hdd/mynode/rtl/RTL-Config.json
fi
# Update for testnet
if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
    sed -i "s/mainnet/testnet/g" /mnt/hdd/mynode/rtl/RTL-Config.json || true
else
    sed -i "s/testnet/mainnet/g" /mnt/hdd/mynode/rtl/RTL-Config.json || true
fi

# BTC RPC Explorer Config
cp /usr/share/mynode/btc_rpc_explorer_env /opt/mynode/btc-rpc-explorer/.env
chown bitcoin:bitcoin /opt/mynode/btc-rpc-explorer/.env

# LNBits Config
if [ -d /opt/mynode/lnbits ]; then
    cp /usr/share/mynode/lnbits.env /opt/mynode/lnbits/.env
    chown bitcoin:bitcoin /opt/mynode/lnbits/.env
fi

# Setup Specter
if [ -d /home/bitcoin/.specter ] && [ ! -L /home/bitcoin/.specter ] ; then
    # Migrate to HDD
    cp -r -f /home/bitcoin/.specter/* /mnt/hdd/mynode/specter/
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/specter
    rm -rf /home/bitcoin/.specter
    sync
fi
if [ ! -L /home/bitcoin/.specter ]; then
    # Setup symlink to HDD
    sudo -u bitcoin ln -s /mnt/hdd/mynode/specter /home/bitcoin/.specter
fi
if [ -f /mnt/hdd/mynode/specter/config.json ]; then
    # Setup config file to point to local bitcoin instance
    BTCRPCPW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
    sed -i "s#\"datadir\": .*#\"datadir\": \"/home/bitcoin/.bitcoin\",#g" /mnt/hdd/mynode/specter/config.json
    sed -i "s#\"user\": .*#\"user\": \"mynode\",#g" /mnt/hdd/mynode/specter/config.json
    sed -i "s#\"password\": .*#\"password\": \"$BTCRPCPW\",#g" /mnt/hdd/mynode/specter/config.json
    sed -i "s#\"port\": .*#\"port\": \"8332\",#g" /mnt/hdd/mynode/specter/config.json
    sed -i "s#\"host\": .*#\"host\": \"localhost\",#g" /mnt/hdd/mynode/specter/config.json
    sed -i "s#\"protocol\": .*#\"protocol\": \"http\"#g" /mnt/hdd/mynode/specter/config.json
fi

# Setup Thunderhub
mkdir -p /mnt/hdd/mynode/thunderhub/
if [ ! -f /mnt/hdd/mynode/thunderhub/.env.local ]; then
    cp -f /usr/share/mynode/thunderhub.env /mnt/hdd/mynode/thunderhub/.env.local
fi
if [ ! -f /mnt/hdd/mynode/thunderhub/thub_config.yaml ]; then
    cp -f /usr/share/mynode/thub_config.yaml /mnt/hdd/mynode/thunderhub/thub_config.yaml
fi
THUNDERHUB_CONFIG_UPDATE_NUM=1
if [ ! -f /mnt/hdd/mynode/thunderhub/update_settings_$THUNDERHUB_CONFIG_UPDATE_NUM ]; then
    cp -f /usr/share/mynode/thunderhub.env /mnt/hdd/mynode/thunderhub/.env.local
    cp -f /usr/share/mynode/thub_config.yaml /mnt/hdd/mynode/thunderhub/thub_config.yaml
fi
if [ -f /mnt/hdd/mynode/thunderhub/thub_config.yaml ]; then
    if [ -f /home/bitcoin/.mynode/.hashedpw_bcrypt ]; then
        HASH_BCRYPT=$(cat /home/bitcoin/.mynode/.hashedpw_bcrypt)
        sed -i "s#masterPassword:.*#masterPassword: \"thunderhub-$HASH_BCRYPT\"#g" /mnt/hdd/mynode/thunderhub/thub_config.yaml
    fi
    if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
        sed -i "s/mainnet/testnet/g" /mnt/hdd/mynode/thunderhub/thub_config.yaml || true
    else
        sed -i "s/testnet/mainnet/g" /mnt/hdd/mynode/thunderhub/thub_config.yaml || true
    fi
fi

chown -R bitcoin:bitcoin /mnt/hdd/mynode/thunderhub

# Setup CKBunker
CKBUNKER_CONFIG_UPDATE_NUM=1
if [ ! -f /mnt/hdd/mynode/ckbunker/update_settings_$CKBUNKER_CONFIG_UPDATE_NUM ]; then
    cp -f /usr/share/mynode/ckbunker_settings.yaml /mnt/hdd/mynode/ckbunker/settings.yaml
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/ckbunker/settings.yaml

    touch /mnt/hdd/mynode/ckbunker/update_settings_$CKBUNKER_CONFIG_UPDATE_NUM
fi

# Setup Sphinx Relay
SPHINXRELAY_CONFIG_UPDATE_NUM=1
if [ ! -f /mnt/hdd/mynode/sphinxrelay/update_settings_$SPHINXRELAY_CONFIG_UPDATE_NUM ]; then
    cp -f /usr/share/mynode/sphinxrelay_app.json /mnt/hdd/mynode/sphinxrelay/app.json
    cp -f /usr/share/mynode/sphinxrelay_config.json /mnt/hdd/mynode/sphinxrelay/config.json
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/sphinxrelay

    touch /mnt/hdd/mynode/sphinxrelay/update_settings_$SPHINXRELAY_CONFIG_UPDATE_NUM
fi
if [ -d /opt/mynode/sphinxrelay/config ]; then
    if [ ! -L /opt/mynode/sphinxrelay/config/app.json ] || [ ! -L /opt/mynode/sphinxrelay/config/config.json ]; then
        rm -f /opt/mynode/sphinxrelay/config/app.json
        rm -f /opt/mynode/sphinxrelay/config/config.json
        sudo -u bitcoin ln -s /mnt/hdd/mynode/sphinxrelay/app.json /opt/mynode/sphinxrelay/config/app.json
        sudo -u bitcoin ln -s /mnt/hdd/mynode/sphinxrelay/config.json /opt/mynode/sphinxrelay/config/config.json
        chown -R bitcoin:bitcoin /opt/mynode/sphinxrelay/config/*
    fi
fi

# Setup JoinMarket
if [ ! -L /home/joinmarket/.joinmarket ]; then
    rm -rf /home/joinmarket/.joinmarket
    sudo -u joinmarket ln -s /mnt/hdd/mynode/joinmarket /home/joinmarket/.joinmarket
fi
# Migrate data from bitcoin user? - Might be confusing later if an old copy of wallet is used
# if [ -f /home/bitcoin/.joinmarket/joinmarket.cfg ] && [ ! -f /mnt/hdd/mynode/joinmarket/joinmarket.cfg ]; then
#     cp /home/bitcoin/.joinmarket/joinmarket.cfg /mnt/hdd/mynode/joinmarket/joinmarket.cfg
# fi
# for f in wallets logs cmtdata; do
#     if [ -d /home/bitcoin/.joinmarket/$f ] && [ ! -d /mnt/hdd/mynode/joinmarket/$f ]; then
#         cp -r /home/bitcoin/.joinmarket/$f /home/joinmarket/.joinmarket/
#     fi
# done
if [ ! -f /mnt/hdd/mynode/joinmarket/joinmarket.cfg ]; then
    cp /usr/share/mynode/joinmarket.cfg /mnt/hdd/mynode/joinmarket/joinmarket.cfg
fi
chown -R joinmarket:joinmarket /mnt/hdd/mynode/joinmarket

# Setup Mempool
cp -f /usr/share/mynode/mempool-docker-compose.yml /mnt/hdd/mynode/mempool/docker-compose.yml
if [ ! -f /mnt/hdd/mynode/mempool/.env ]; then
    cp -f /usr/share/mynode/mempool.env /mnt/hdd/mynode/mempool/.env
fi
if [ $IS_RASPI -eq 1 ]; then
    sed -i "s|MARIA_DB_IMAGE=.*|MARIA_DB_IMAGE=hypriot/rpi-mysql:latest|g" /mnt/hdd/mynode/mempool/.env
fi

# Backup Tor files
for f in /var/lib/tor/mynode*; do
    rsync --ignore-existing -r -avh $f /mnt/hdd/mynode/tor_backup/ || true
done
cp -a -f /mnt/hdd/mynode/tor_backup/. /var/lib/tor/ || true
chown debian-tor:debian-tor /var/lib/tor
systemctl restart tor || true

# Setup udev
chown root:root /etc/udev/rules.d/* || true
udevadm trigger
udevadm control --reload-rules
groupadd plugdev || true
sudo usermod -aG plugdev bitcoin

# Update other files that need RPC password (needed if upgrades overwrite files)
BTCRPCPW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
if [ -f /opt/mynode/LndHub/config.js ]; then
    cp -f /usr/share/mynode/lndhub-config.js /opt/mynode/LndHub/config.js
    sed -i "s/mynode:.*@/mynode:$BTCRPCPW@/g" /opt/mynode/LndHub/config.js
    chown bitcoin:bitcoin /opt/mynode/LndHub/config.js
fi
if [ -f /opt/mynode/btc-rpc-explorer/.env ]; then
    sed -i "s/BTCEXP_BITCOIND_PASS=.*/BTCEXP_BITCOIND_PASS=$BTCRPCPW/g" /opt/mynode/btc-rpc-explorer/.env
fi
if [ -f /mnt/hdd/mynode/joinmarket/joinmarket.cfg ]; then
    sed -i "s/rpc_password = .*/rpc_password = $BTCRPCPW/g" /mnt/hdd/mynode/joinmarket/joinmarket.cfg
fi
if [ -f /mnt/hdd/mynode/lit/lit.conf ]; then
    sed -i "s/faraday.bitcoin.password=.*/faraday.bitcoin.password=$BTCRPCPW/g" /mnt/hdd/mynode/lit/lit.conf
fi
if [ -f /mnt/hdd/mynode/mempool/.env ]; then
    sed -i "s/BITCOIN_RPC_PASS=.*/BITCOIN_RPC_PASS=$BTCRPCPW/g" /mnt/hdd/mynode/mempool/.env
fi
echo "BTC_RPC_PASSWORD=$BTCRPCPW" > /mnt/hdd/mynode/settings/.btcrpc_environment
chown bitcoin:bitcoin /mnt/hdd/mynode/settings/.btcrpc_environment
if [ -f /mnt/hdd/mynode/bitcoin/bitcoin.conf ]; then
    sed -i "s/rpcauth=.*/$RPCAUTH/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
fi


# Append bitcoin UID and GID to btcrpc_environment
BITCOIN_UID=$(id -u bitcoin)
BITCOIN_GID=$(id -g bitcoin)
echo "BITCOIN_UID=$BITCOIN_UID" >> /mnt/hdd/mynode/settings/.btcrpc_environment
echo "BITCOIN_GID=$BITCOIN_GID" >> /mnt/hdd/mynode/settings/.btcrpc_environment


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
USER=$(stat -c '%U' /mnt/hdd/mynode/loop)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/loop
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/pool)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/pool
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/faraday)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/faraday
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/lit)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/lit
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/whirlpool)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/whirlpool
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/lnbits)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/lnbits
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/rtl)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/rtl
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/specter)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/specter
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/ckbunker)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/ckbunker
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/sphinxrelay)
if [ "$USER" != "bitcoin" ]; then
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/sphinxrelay
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/joinmarket)
if [ "$USER" != "joinmarket" ]; then
    chown -R joinmarket:joinmarket /mnt/hdd/mynode/joinmarket
fi
USER=$(stat -c '%U' /mnt/hdd/mynode/tor_backup)
if [ "$USER" != "debian-tor" ]; then
    chown -R debian-tor:debian-tor /mnt/hdd/mynode/tor_backup
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
if [ ! -f /mnt/hdd/mynode/settings/swap_size ]; then
    # Set defaults
    touch /mnt/hdd/mynode/settings/swap_size
    echo "2" > /mnt/hdd/mynode/settings/swap_size
    sed -i "s|CONF_SWAPSIZE=.*|CONF_SWAPSIZE=2048|" /etc/dphys-swapfile
else
    # Update swap config file in case upgrade overwrote file
    SWAP=$(cat /mnt/hdd/mynode/settings/swap_size)
    SWAP_MB=$(($SWAP * 1024))
    sed -i "s|CONF_SWAPSIZE=.*|CONF_SWAPSIZE=$SWAP_MB|" /etc/dphys-swapfile
fi

SWAP=$(cat /mnt/hdd/mynode/settings/swap_size)
if [ "$SWAP" -ne "0" ]; then
    dphys-swapfile install || true
    dphys-swapfile swapon || true
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

# Generate certificates
echo "Generating certificates..."
/usr/bin/mynode_gen_cert.sh https 825
/usr/bin/mynode_gen_cert_electrs.sh

# Setup nginx HTTPS proxy
mkdir -p /var/log/nginx || true
mkdir -p /etc/nginx || true
rm -f /etc/nginx/modules-enabled/50-mod-* || true # Remove unnecessary files
echo "gen_dhparam" > $MYNODE_STATUS_FILE
/usr/bin/mynode_gen_dhparam.sh
echo "drive_mounted" > $MYNODE_STATUS_FILE
cp -f /usr/share/mynode/nginx.conf /etc/nginx/nginx.conf
systemctl restart nginx || true


# Update latest version files
echo $BTC_VERSION > $BTC_LATEST_VERSION_FILE
echo $LND_VERSION > $LND_LATEST_VERSION_FILE
echo $LIT_VERSION > $LIT_LATEST_VERSION_FILE
echo $ELECTRS_VERSION > $ELECTRS_LATEST_VERSION_FILE
echo $LNDHUB_VERSION > $LNDHUB_LATEST_VERSION_FILE
echo $CARAVAN_VERSION > $CARAVAN_LATEST_VERSION_FILE
echo $CORSPROXY_VERSION > $CORSPROXY_LATEST_VERSION_FILE
echo $JOINMARKET_VERSION > $JOINMARKET_LATEST_VERSION_FILE
echo $JOININBOX_VERSION > $JOININBOX_LATEST_VERSION_FILE
echo $WHIRLPOOL_VERSION > $WHIRLPOOL_LATEST_VERSION_FILE
echo $RTL_VERSION > $RTL_LATEST_VERSION_FILE
echo $BTCRPCEXPLORER_VERSION > $BTCRPCEXPLORER_LATEST_VERSION_FILE
echo $LNBITS_VERSION > $LNBITS_LATEST_VERSION_FILE
echo $SPECTER_VERSION > $SPECTER_LATEST_VERSION_FILE
echo $THUNDERHUB_VERSION > $THUNDERHUB_LATEST_VERSION_FILE
echo $LNDCONNECT_VERSION > $LNDCONNECT_LATEST_VERSION_FILE
echo $CKBUNKER_VERSION > $CKBUNKER_LATEST_VERSION_FILE
echo $SPHINXRELAY_VERSION > $SPHINXRELAY_LATEST_VERSION_FILE


# Weird hacks
chmod +x /usr/bin/electrs || true # Once, a device didn't have the execute bit set for electrs
timedatectl set-ntp True || true # Make sure NTP is enabled for Tor and Bitcoin
rm -f /var/swap || true # Remove old swap file to save SD card space
systemctl enable check_in || true


# Check for new versions
torify wget $LATEST_VERSION_URL --timeout=30 -O /usr/share/mynode/latest_version || true
torify wget $LATEST_BETA_VERSION_URL --timeout=30 -O /usr/share/mynode/latest_beta_version || true

# Update current state
if [ -f $QUICKSYNC_DIR/.quicksync_complete ]; then
    echo "stable" > $MYNODE_STATUS_FILE
fi
