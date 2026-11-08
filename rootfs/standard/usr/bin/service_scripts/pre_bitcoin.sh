#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

# Try to migrate wallet.dat
if [ -f /mnt/hdd/mynode/bitcoin/wallet.dat ]; then
    mkdir -p /mnt/hdd/mynode/bitcoin/wallet_folder.dat
    mv /mnt/hdd/mynode/bitcoin/wallet.dat /mnt/hdd/mynode/bitcoin/wallet_folder.dat/wallet.dat
    mv /mnt/hdd/mynode/bitcoin/wallet_folder.dat /mnt/hdd/mynode/bitcoin/wallet.dat
    chown -R bitcoin:bitcoin /mnt/hdd/mynode/bitcoin/wallet.dat
fi

# Bitcoin Core 30 and newer cannot load legacy (BDB) wallets. Move JoinMarket's old watch-only wallet
# aside; MyNode creates a descriptor wallet with the same name once Bitcoin is synced.
BTC_MAJOR_VERSION=$(/usr/local/bin/bitcoind --version 2>/dev/null | head -1 | grep -o "v[0-9][0-9]*" | head -1 | tr -d v)
if [ "${BTC_MAJOR_VERSION:-0}" -ge 30 ]; then
    for wallet in /mnt/hdd/mynode/bitcoin/joinmarket_wallet.dat /mnt/hdd/mynode/bitcoin/testnet3/wallets/joinmarket_wallet.dat; do
        wallet_file="$wallet"
        if [ -d "$wallet" ]; then
            wallet_file="$wallet/wallet.dat"
        fi
        if [ -f "$wallet_file" ] && [ ! -L "$wallet" ] && [ "$(head -c 15 "$wallet_file")" != "SQLite format 3" ]; then
            backup="$wallet.legacy-bdb"
            if [ -e "$backup" ]; then
                backup="$wallet.legacy-bdb.$(date +%s)"
            fi
            mv -T "$wallet" "$backup"
        fi
    done
fi

rm -f /mnt/hdd/mynode/bitcoin/settings.json

# Sync FS
sync