#!/bin/bash

# Device info
IS_ARMBIAN=0
IS_ROCK64=0
IS_ROCKPRO64=0
IS_RASPI=0
IS_RASPI3=0
IS_RASPI4=0
IS_X86=0
DEVICE_TYPE="unknown"
MODEL=$(cat /proc/device-tree/model) || MODEL="unknown"
uname -a | grep amd64 && IS_X86=1 || true
if [[ $MODEL == *"Rock64"* ]]; then 
    IS_ARMBIAN=1
    IS_ROCK64=1
elif [[ $MODEL == *"RockPro64"* ]]; then 
    IS_ARMBIAN=1
    IS_ROCKPRO64=1
elif [[ $MODEL == *"Raspberry Pi 3"* ]]; then
    IS_RASPI=1
    IS_RASPI3=1
elif [[ $MODEL == *"Raspberry Pi 4"* ]]; then
    IS_RASPI=1
    IS_RASPI4=1
fi

if [ $IS_RASPI3 -eq 1 ]; then
    DEVICE_TYPE="raspi3"
elif [ $IS_RASPI4 -eq 1 ]; then
    DEVICE_TYPE="raspi4"
elif [ $IS_ROCK64 -eq 1 ]; then
    DEVICE_TYPE="rock64"
elif [ $IS_ROCKPRO64 -eq 1 ]; then
    DEVICE_TYPE="rockpro64"
elif [ $IS_X86 -eq 1 ]; then
    DEVICE_TYPE="debian"
fi


SERIAL_NUM=$(cat /proc/cpuinfo | grep Serial | cut -d ' ' -f 2)
if [[ "$SERIAL_NUM" == "" ]]; then
    SERIAL_NUM=$(sudo dmidecode | grep UUID | cut -d ' ' -f 2)
fi

# Set all default / standard bash config settings
MYNODE_DIR=/mnt/hdd/mynode
VPN_BACKUP_DIR=/mnt/hdd/mynode/vpn
QUICKSYNC_DIR=/mnt/hdd/mynode/quicksync
QUICKSYNC_CONFIG_DIR=/mnt/hdd/mynode/.config/transmission
QUICKSYNC_TORRENT_URL="https://mynodebtc.com/device/blockchain.tar.gz.torrent"
QUICKSYNC_TORRENT_BETA_URL="https://mynodebtc.com/device/blockchain_beta.tar.gz.torrent"
QUICKSYNC_UPLOAD_RATE_FILE="/mnt/hdd/mynode/settings/quicksync_upload_rate"
QUICKSYNC_BACKGROUND_DOWNLOAD_RATE_FILE="/mnt/hdd/mynode/settings/quicksync_background_download_rate"
LATEST_VERSION_URL="http://www.mynodebtc.com/device/latest_version"
UPLOADER_FILE="/mnt/hdd/mynode/settings/uploader"
UPGRADE_ERROR_FILE="/mnt/hdd/mynode/settings/upgrade_error"
LND_BACKUP_FOLDER="/home/bitcoin/lnd_backup/"
LND_TLS_CERT_FILE="/mnt/hdd/mynode/lnd/tls.cert"
LND_WALLET_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/wallet.db"
LND_CHANNEL_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/channel.backup"
LND_CHANNEL_FILE_BACKUP="/home/bitcoin/lnd_backup/channel.backup"
LND_ADMIN_MACAROON_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon"
PRODUCT_KEY_FILE="/home/bitcoin/.mynode/.product_key"

ELECTRS_ENABLED_FILE="/mnt/hdd/mynode/.mynode_electrs_enabled"
LNDHUB_ENABLED_FILE="/mnt/hdd/mynode/.mynode_lndhub_enabled"
BTCRPCEXPLORER_ENABLED_FILE="/mnt/hdd/mynode/.mynode_btcrpceplorer_enabled"
VPN_ENABLED_FILE="/mnt/hdd/mynode/.mynode_vpn_enabled"

BITCOIN_SYNCED_FILE="/mnt/hdd/mynode/.mynode_bitcoind_synced"
QUICKSYNC_COMPLETE_FILE="$QUICKSYNC_DIR/.quicksync_complete"

IS_PREMIUM=0
PRODUCT_KEY="not_found"
if [ -f $PRODUCT_KEY_FILE ]; then
    PRODUCT_KEY=$(cat $PRODUCT_KEY_FILE)
    if [ ! -f /home/bitcoin/.mynode/.product_key_skipped ] && [ ! -f /mnt/hdd/mynode/settings/.product_key_skipped ]; then
        if [ ! -f /home/bitcoin/.mynode/.product_key_error ] && [ ! -f /mnt/hdd/mynode/settings/.product_key_error ]; then
            IS_PREMIUM=1
        fi
    fi
fi

UPGRADE_DOWNLOAD_URL="http://www.mynodebtc.com/device_api/download_latest_standard.php?type=${DEVICE_TYPE}&product_key=${PRODUCT_KEY}&serial=${SERIAL_NUM}"
UPGRADE_DOWNLOAD_SIGNATURE_URL="http://www.mynodebtc.com/device/hashes/mynode_release_latest_${DEVICE_TYPE}.sha256"
UPGRADE_PUBKEY_URL="https://raw.githubusercontent.com/mynodebtc/pubkey/master/mynode_release.pub"

# Update settings for other devices
if [ -f /usr/share/mynode/mynode_config_raspi.sh ]; then
    source /usr/share/mynode/mynode_config_raspi.sh
fi
if [ -f /usr/share/mynode/mynode_config_debian.sh ]; then
    source /usr/share/mynode/mynode_config_debian.sh
fi