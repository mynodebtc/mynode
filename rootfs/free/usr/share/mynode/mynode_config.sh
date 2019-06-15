#!/bin/bash

# Device info
IS_RASPI=1
IS_ROCK64=0

# Set all default / standard bash config settings
MYNODE_DIR=/mnt/hdd/mynode
QUICKSYNC_DIR=/mnt/hdd/mynode/quicksync
QUICKSYNC_CONFIG_DIR=/home/bitcoin/.config/transmission
QUICKSYNC_TORRENT_URL="https://mynodebtc.com/device/blockchain.tar.gz.torrent"
QUICKSYNC_BANDWIDTH_FILE="/home/bitcoin/.mynode/.bandwidth"
LND_BACKUP_FOLDER="/home/bitcoin/lnd_backup/"
LND_TLS_CERT_FILE="/mnt/hdd/mynode/lnd/tls.cert"
LND_WALLET_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/wallet.db"
LND_CHANNEL_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/channel.backup"
LND_CHANNEL_FILE_BACKUP="/home/bitcoin/lnd_backup/channel.backup"
LND_ADMIN_MACAROON_FILE="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon"

UPGRADE_DOWNLOAD_URL="http://www.mynodebtc.com/device/mynode_release_latest_free.tar.gz"
UPGRADE_DOWNLOAD_SIGNATURE_URL="http://www.mynodebtc.com/device/mynode_release_latest_free.sha256"
UPGRADE_PUBKEY_URL="https://raw.githubusercontent.com/mynodebtc/pubkey/master/mynode_release.pub"