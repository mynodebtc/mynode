#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh

# Set all default / standard bash config settings
MYNODE_DIR=/mnt/hdd/mynode
MYNODE_STATUS_FILE=/tmp/.mynode_status
DEVICE_ARCHITECTURE_FILE="/mnt/hdd/mynode/settings/.device_arch"
VPN_BACKUP_DIR=/mnt/hdd/mynode/vpn
QUICKSYNC_DIR=/mnt/hdd/mynode/quicksync
QUICKSYNC_CONFIG_DIR=/mnt/hdd/mynode/.config/transmission
QUICKSYNC_TORRENT_URL="https://mynodebtc.com/device/blockchain.tar.gz.torrent"
QUICKSYNC_TORRENT_BETA_URL="https://mynodebtc.com/device/blockchain_beta.tar.gz.torrent"
QUICKSYNC_UPLOAD_RATE_FILE="/mnt/hdd/mynode/settings/quicksync_upload_rate"
QUICKSYNC_BACKGROUND_DOWNLOAD_RATE_FILE="/mnt/hdd/mynode/settings/quicksync_background_download_rate"
LATEST_VERSION_URL="https://www.mynodebtc.com/device_api/get_latest_version.php?type=${DEVICE_TYPE}"
LATEST_BETA_VERSION_URL="https://www.mynodebtc.com/device_api/get_latest_version.php?type=${DEVICE_TYPE}&beta=1"
UPLOADER_FILE="/mnt/hdd/mynode/settings/uploader"
UPGRADE_ERROR_FILE="/mnt/hdd/mynode/settings/upgrade_error"
LND_BACKUP_FOLDER="/home/bitcoin/lnd_backup/"
LND_TLS_CERT_FILE="/mnt/hdd/mynode/lnd/tls.cert"
LND_WALLET_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/wallet.db"
LND_CHANNEL_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/channel.backup"
LND_CHANNEL_FILE_BACKUP="/home/bitcoin/lnd_backup/channel.backup"
LND_ADMIN_MACAROON_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon"
PRODUCT_KEY_FILE="/home/bitcoin/.mynode/.product_key"
IS_TESTNET_ENABLED_FILE="/mnt/hdd/mynode/settings/.testnet_enabled"

if [ -f $IS_TESTNET_ENABLED_FILE ]; then
    LND_WALLET_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/testnet/wallet.db"
    LND_CHANNEL_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/testnet/channel.backup"
    LND_CHANNEL_FILE_BACKUP="/home/bitcoin/lnd_backup/channel_testnet.backup"
    LND_ADMIN_MACAROON_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/testnet/admin.macaroon"
fi

BITCOIN_SYNCED_FILE="/mnt/hdd/mynode/.mynode_bitcoin_synced"
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

UPGRADE_DOWNLOAD_URL="https://www.mynodebtc.com/device_api/download_latest_standard.php?type=${DEVICE_TYPE}&product_key=${PRODUCT_KEY}"
UPGRADE_DOWNLOAD_SIGNATURE_URL="https://www.mynodebtc.com/device_api/download_latest_standard.php?type=${DEVICE_TYPE}&product_key=${PRODUCT_KEY}&hash=1"
UPGRADE_BETA_DOWNLOAD_URL="https://www.mynodebtc.com/device_api/download_latest_standard.php?type=${DEVICE_TYPE}&product_key=${PRODUCT_KEY}&beta=1"
UPGRADE_BETA_DOWNLOAD_SIGNATURE_URL="https://www.mynodebtc.com/device_api/download_latest_standard.php?type=${DEVICE_TYPE}&product_key=${PRODUCT_KEY}&beta=1&hash=1"
UPGRADE_PUBKEY_URL="https://raw.githubusercontent.com/mynodebtc/pubkey/master/mynode_release.pub"

# Update settings for other devices
if [ -f /usr/share/mynode/mynode_config_raspi.sh ]; then
    source /usr/share/mynode/mynode_config_raspi.sh
fi
if [ -f /usr/share/mynode/mynode_config_debian.sh ]; then
    source /usr/share/mynode/mynode_config_debian.sh
fi