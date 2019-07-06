#!/bin/bash

# Device info
IS_RASPI=0
IS_RASPI3=0
IS_RASPI4=0
IS_ROCK64=1
IS_STANDARD=1
DEVICE_TYPE="rock64"

SERIAL_NUM=$(cat /proc/cpuinfo | grep Serial | cut -d ' ' -f 2)

# Set all default / standard bash config settings
MYNODE_DIR=/mnt/hdd/mynode
QUICKSYNC_DIR=/mnt/hdd/mynode/quicksync
QUICKSYNC_CONFIG_DIR=/home/bitcoin/.config/transmission
QUICKSYNC_TORRENT_URL="https://mynodebtc.com/device/blockchain.tar.gz.torrent"
QUICKSYNC_BANDWIDTH_FILE="/mnt/hdd/mynode/settings/.bandwidth"
LND_BACKUP_FOLDER="/home/bitcoin/lnd_backup/"
LND_TLS_CERT_FILE="/mnt/hdd/mynode/lnd/tls.cert"
LND_WALLET_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/wallet.db"
LND_CHANNEL_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/channel.backup"
LND_CHANNEL_FILE_BACKUP="/home/bitcoin/lnd_backup/channel.backup"
LND_ADMIN_MACAROON_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon"
PRODUCT_KEY_FILE="/home/bitcoin/.mynode/.product_key"

PRODUCT_KEY="not_found"
if [ -f $PRODUCT_KEY_FILE ]; then
    PRODUCT_KEY=$(cat $PRODUCT_KEY_FILE)
fi

UPGRADE_DOWNLOAD_URL="http://www.mynodebtc.com/device_api/download_latest_standard.php?type=${DEVICE_TYPE}&product_key=${PRODUCT_KEY}&serial=${SERIAL_NUM}"
UPGRADE_DOWNLOAD_SIGNATURE_URL="http://www.mynodebtc.com/device/hashes/mynode_release_latest_${DEVICE_TYPE}.sha256"
UPGRADE_PUBKEY_URL="https://raw.githubusercontent.com/mynodebtc/pubkey/master/mynode_release.pub"

# Update settings for other devices
if [ -f /usr/share/mynode/mynode_config_raspi.sh ]; then
    source /usr/share/mynode/mynode_config_raspi.sh
fi