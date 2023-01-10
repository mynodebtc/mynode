#!/bin/bash

set -e
set -x 
shopt -s nullglob

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_functions.sh
source /usr/share/mynode/mynode_app_versions.sh

# Verify FS is mounted as R/W
if [ ! -w / ]; then
    touch /tmp/sd_rw_error
    mount -o remount,rw /;
fi

# Set sticky bit on /tmp
chmod +t /tmp

# Save dmidecode info
dmidecode | grep UUID | cut -d ' ' -f 2 > /tmp/dmidecode_serial

# Add some DNS servers to make domain lookup more likely
if settings_file_exists "skip_backup_dns_servers" ; then
    echo '' >> /etc/resolv.conf
    sed -i "s/^.*append domain-name-servers/#append domain-name-servers/g" /etc/dhcp/dhclient.conf || true
else
    needDns=0
    grep "Added at myNode startup" /etc/resolv.conf || needDns=1
    if [ $needDns = 1 ]; then
        echo '' >> /etc/resolv.conf
        echo '# Added at myNode startup' >> /etc/resolv.conf
        echo 'nameserver 1.1.1.1' >> /etc/resolv.conf
        echo 'nameserver 208.67.222.222' >> /etc/resolv.conf
        echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
    fi
    sed -i "s/^.*append domain-name-servers .*/append domain-name-servers 1.1.1.1, 208.67.222.222, 8.8.8.8;/g" /etc/dhcp/dhclient.conf || true
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
    #if [ $IS_ROCK64 = 1 ] || [ $IS_ROCKPRO64 = 1 ] || [ $IS_ROCKPI4 = 1 ]; then
    if [ $IS_ARMBIAN = 1 ]; then
        /usr/lib/armbian/armbian-resize-filesystem start
        touch /var/lib/mynode/.expanded_rootfs 
    fi
    if [ $IS_X86 = 1 ]; then
        X86_ROOT_PARTITION="$(mount | grep ' / ' | cut -d ' ' -f1)"
        X86_DEVICE="$(lsblk -no pkname $X86_ROOT_PARTITION)"
        X86_DEVICE_PATH="/dev/$X86_DEVICE"
        case "$X86_DEVICE" in
            sd* | hd* | vd*)
                # SATA
                X86_PARTITION_NUMBER=$(cat /proc/partitions | grep -c "${X86_DEVICE}[0-9]")
                ;;
            nvme*)
                # NVMe
                X86_PARTITION_NUMBER=$(cat /proc/partitions | grep -c "${X86_DEVICE}p[0-9]")
                ;;            
        esac

        if [ $X86_DEVICE = "sda" ]; then
            # SATA
            
        else
            # NVMe
            
        fi        
        X86_FDISK_TYPE=$(fdisk -l "$X86_DEVICE_PATH" | grep "Disklabel")
        echo "Root Partition:   $X86_ROOT_PARTITION"
        echo "Root Device:      $X86_DEVICE"
        echo "Root Dev Path:    $X86_DEVICE_PATH"
        echo "Root Partition #: $X86_PARTITION_NUMBER"
        if [[ "$X86_FDISK_TYPE" = *"Disklabel type: gpt"* ]]; then
            if [ "$X86_PARTITION_NUMBER" = "2" ]; then
                sgdisk -e $X86_DEVICE_PATH
                sgdisk -d $X86_PARTITION_NUMBER $X86_DEVICE_PATH
                sgdisk -N $X86_PARTITION_NUMBER $X86_DEVICE_PATH
                partprobe $X86_DEVICE_PATH
                resize2fs $X86_ROOT_PARTITION
                touch /var/lib/mynode/.expanded_rootfs
            else
                echo "Not resizing - Expected 2 partitions, found $X86_PARTITION_NUMBER"
            fi
        else
            echo "Not resizing - Expected GPT partition"
            echo "$X86_FDISK"
        fi
    fi
fi


# Setup SD Card (if necessary)
mkdir -p /run/tor
mkdir -p /var/run/tor
mkdir -p /home/bitcoin/.mynode/
mkdir -p /home/admin/.bitcoin/
mkdir -p /etc/torrc.d
chown admin:admin /home/admin/.bitcoin/
rm -rf /etc/motd # Remove simple motd for update-motd.d

mkdir -p /mnt/hdd
mkdir -p /mnt/usb_extras

# Add to python path
[ -d /usr/local/lib/python2.7/dist-packages ] && echo "/var/pynode" > /usr/local/lib/python2.7/dist-packages/pynode.pth
[ -d /usr/local/lib/python3.7/site-packages ] && echo "/var/pynode" > /usr/local/lib/python3.7/site-packages/pynode.pth
[ -d /usr/local/lib/python3.8/site-packages ] && echo "/var/pynode" > /usr/local/lib/python3.8/site-packages/pynode.pth

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

# Check for USB driver updates before mount or clone tool opening
/usr/local/bin/python3 /usr/bin/mynode_usb_driver_check.py

# Clone tool was opened
if [ -f /home/bitcoin/open_clone_tool ]; then
    rm -f /home/bitcoin/open_clone_tool
    echo "drive_clone" > $MYNODE_STATUS_FILE
    sync
    while [ 1 ]; do
        python3 /usr/bin/clone_drive.py || true
    done
fi


# Check drive (only if exactly 1 is found)
set +e
if [ $IS_X86 = 0 ]; then
    if [ ! -f /home/bitcoin/.mynode/skip_fsck ]; then
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
fi
rm -f /tmp/repairing_drive
set -e

# Delay startup for checking drives, etc..
while [ -f /home/bitcoin/.mynode/delay_startup ]; do
    sleep 5s
done

# Custom startup hook - pre-startup
if [ -f /usr/local/bin/mynode_hook_pre_startup.sh ]; then
    /bin/bash /usr/local/bin/mynode_hook_pre_startup.sh || true
fi

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
    # Show status
    echo "docker_reset" > $MYNODE_STATUS_FILE
    chmod 777 $MYNODE_STATUS_FILE

    # Delete docker data
    rm -rf /mnt/hdd/mynode/docker
    rm /home/bitcoin/reset_docker
    sync
    reboot
    sleep 60s
    exit 0
fi


# Check drive usage
mb_available=$(df --block-size=M /mnt/hdd | grep /dev | awk '{print $4}' | cut -d'M' -f1)
while [ $mb_available -le 2000 ]; do
    echo "drive_full" > $MYNODE_STATUS_FILE
    sleep 60s
    mb_available=$(df --block-size=M /mnt/hdd | grep /dev | awk '{print $4}' | cut -d'M' -f1)
done


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
rm -rf $MYNODE_DIR/.mynode_bitcoin_synced


# Sync product key (SD preferred)
cp -f /home/bitcoin/.mynode/.product_key* /mnt/hdd/mynode/settings/ || true
cp -f /mnt/hdd/mynode/settings/.product_key* home/bitcoin/.mynode/ || true

# Make any users we need to
useradd -m -s /bin/bash pivpn || true
useradd -m -s /bin/bash joinmarket || true

# User updates and settings
adduser admin bitcoin
adduser joinmarket bitcoin
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
    # QuickSync defaults to disabled, needs to be manually enabled if wanted
    touch /mnt/hdd/mynode/settings/quicksync_disabled
    
    touch /mnt/hdd/mynode/settings/.setquicksyncdefault
fi


# Migrate from version file to version+install combo
/usr/bin/mynode_migrate_version_files.sh

# Choose Network Prompt if no defaults are set (should happen only on first setup)
if [ ! -f /mnt/hdd/mynode/settings/btc_network_settings_defaulted ] && 
   [ ! -f /home/bitcoin/.mynode/btc_network_settings_defaulted ] &&
   [ ! -f /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled_defaulted ] && 
   [ ! -f /home/bitcoin/.mynode/.btc_lnd_tor_enabled_defaulted ]; then
    echo "choose_network" > $MYNODE_STATUS_FILE
    while [ ! -f /mnt/hdd/mynode/settings/btc_network_settings_defaulted ]; do
        sleep .25s
    done
fi
echo "drive_mounted" > $MYNODE_STATUS_FILE

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
# Remove old electrs data (pre-v9)
rm -rf /mnt/hdd/mynode/electrs/mainnet
# Use correct binary on RP4 (32 bit/64bit)
if [ $IS_RASPI4 -eq 1 ]; then
    ELECTRS_DST=/usr/bin/electrs
    ELECTRS_SRC=/usr/bin/electrs_arm32
    if [ $IS_RASPI4_ARM64 -eq 1 ]; then
        ELECTRS_SRC=/usr/bin/electrs_arm64
    fi
    if [ ! -f $ELECTRS_DST ]; then
        cp -f $ELECTRS_SRC $ELECTRS_DST
    else
        MD5_1=$(md5sum $ELECTRS_DST | cut -d' ' -f 1)
        MD5_2=$(md5sum $ELECTRS_SRC | cut -d' ' -f 1)
        if [ "${MD5_1}" != "{$MD5_2}" ]; then
            cp -f $ELECTRS_SRC $ELECTRS_DST
        fi
    fi
fi

# RTL config
# Moved to pre_rtl.sh

# BTCPay Server Setup
# Now in mynode_docker_images.sh (any new setup should go into pre_btcpayserver.sh)

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
sed -i "s/#max_cj_fee_abs = x/max_cj_fee_abs = 2000/g" /mnt/hdd/mynode/joinmarket/joinmarket.cfg
sed -i "s/#max_cj_fee_rel = x/max_cj_fee_rel = 0.001/g" /mnt/hdd/mynode/joinmarket/joinmarket.cfg
chown -R joinmarket:joinmarket /mnt/hdd/mynode/joinmarket

# Setup Mempool
# Moved to pre_mempool.sh

# Setup Netdata
mkdir -p /opt/mynode/netdata
cp -f /usr/share/mynode/netdata-compose.yml /opt/mynode/netdata/netdata-compose.yml
echo "NETDATA_VERSION=${NETDATA_VERSION}" > /opt/mynode/netdata/.env
cp -f /usr/share/mynode/netdata.conf /opt/mynode/netdata/netdata.conf

# Setup webssh2
mkdir -p /opt/mynode/webssh2
cp -f /usr/share/mynode/webssh2_config.json /opt/mynode/webssh2/config.json

# Initialize Dynamic Apps
mynode-manage-apps init || true
mynode-manage-apps openports || true

# Backup Tor files
for f in /var/lib/tor/mynode*; do
    rsync --ignore-existing -r -avh $f /mnt/hdd/mynode/tor_backup/ || true
done
cp -a -f /mnt/hdd/mynode/tor_backup/. /var/lib/tor/ || true
chown -R debian-tor:debian-tor /var/lib/tor
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
    #sed -i "s/mynode:.*@/mynode:$BTCRPCPW@/g" /opt/mynode/LndHub/config.js
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
echo "BTC_RPC_PASSWORD=$BTCRPCPW" > /mnt/hdd/mynode/settings/.btcrpc_environment
chown bitcoin:bitcoin /mnt/hdd/mynode/settings/.btcrpc_environment
if [ -f /mnt/hdd/mynode/bitcoin/bitcoin.conf ]; then
    sed -i "s/rpcauth=.*/$RPCAUTH/g" /mnt/hdd/mynode/bitcoin/bitcoin.conf
fi
if [ -f /mnt/hdd/mynode/dojo/docker/my-dojo/conf/docker-bitcoind.conf ]; then
    sed -i "s/BITCOIND_RPC_PASSWORD=.*/BITCOIND_RPC_PASSWORD=$BTCRPCPW/g" /mnt/hdd/mynode/dojo/docker/my-dojo/conf/docker-bitcoind.conf
fi
if [ -f /mnt/hdd/mynode/dojo/docker/my-dojo/conf/docker-bitcoind.conf.tpl ]; then
    sed -i "s/BITCOIND_RPC_PASSWORD=.*/BITCOIND_RPC_PASSWORD=$BTCRPCPW/g" /mnt/hdd/mynode/dojo/docker/my-dojo/conf/docker-bitcoind.conf.tpl
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
mkdir -p $LND_BACKUP_FOLDER
chown -R bitcoin:bitcoin $LND_BACKUP_FOLDER


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
# FUTURE: Loop over service names with enable / disable possibility like
# services=electrs lndhub btcrpcexplorer mempool btcpayserver vpn ...
# for s in services; do
#   if [ -f /mnt/hdd/mynode/settings/${s}_enabled ]; then
#     if systemctl status $s | grep "disabled;"; then
#       systemctl enable $s
#       STARTUP_MODIFIED=1
#     fi
#   fi
# done


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
/usr/bin/mynode_update_latest_version_files.sh
touch /tmp/need_application_refresh

# Mark some internal app versions
echo "v1.0" > /home/bitcoin/.mynode/tor_version
echo "v1.0" > /home/bitcoin/.mynode/vpn_version
echo "v1.0" > /home/bitcoin/.mynode/premium_plus_version

# Weird hacks
chmod +x /usr/bin/electrs || true # Once, a device didn't have the execute bit set for electrs
timedatectl set-ntp True || true # Make sure NTP is enabled for Tor and Bitcoin
rm -f /var/swap || true # Remove old swap file to save SD card space
systemctl enable check_in || true
systemctl enable premium_plus_connect || true
systemctl enable bitcoin || true                # Make sure new bitcoin service is used
systemctl disable bitcoind || true              # Make sure new bitcoin service is used
rm /etc/systemd/system/bitcoind.service || true # Make sure new bitcoin service is used
systemctl daemon-reload || true
if [ -f /usr/share/joininbox/menu.update.sh ] && [ -f /home/joinmarket/menu.update.sh ]; then
    sudo -u joinmarket cp -f /usr/share/joininbox/menu.update.sh /home/joinmarket/menu.update.sh
fi
chown bitcoin:bitcoin /mnt/hdd/mynode/settings/.lndpw || true

# Custom startup hook - post-startup
if [ -f /usr/local/bin/mynode_hook_post_startup.sh ]; then
    /bin/bash /usr/local/bin/mynode_hook_post_startup.sh || true
fi

# Update current state
if [ -f $QUICKSYNC_DIR/.quicksync_complete ]; then
    echo "stable" > $MYNODE_STATUS_FILE
fi
