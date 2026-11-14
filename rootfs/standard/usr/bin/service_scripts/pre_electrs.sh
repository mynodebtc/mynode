#!/bin/bash

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

# Setup electrs
cp -f /usr/share/mynode/electrs.toml /mnt/hdd/mynode/electrs/electrs.toml

# Update for testnet
if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
    sed -i "s/bitcoin/testnet/g" /mnt/hdd/mynode/electrs/electrs.toml || true
else
    sed -i "s/testnet/bitcoin/g" /mnt/hdd/mynode/electrs/electrs.toml || true
fi

# Update for tx limit
INDEX_LOOKUP_LIMIT=200
if [ $IS_X86 = 1 ]; then
    INDEX_LOOKUP_LIMIT=1000
fi
if [ -f /mnt/hdd/mynode/electrs/index_lookup_limit ]; then
    SAVED_LIMIT=$(cat /mnt/hdd/mynode/electrs/index_lookup_limit)
    if [[ "$SAVED_LIMIT" =~ ^[0-9]{1,7}$ ]]; then
        INDEX_LOOKUP_LIMIT=$SAVED_LIMIT
    else
        echo "Ignoring invalid index_lookup_limit"
    fi
fi
if [ ! -f /mnt/hdd/mynode/electrs/index_lookup_limit ]; then
    echo "$INDEX_LOOKUP_LIMIT" > /mnt/hdd/mynode/electrs/index_lookup_limit
fi
sed -i "s/index_lookup_limit =.*/index_lookup_limit = $INDEX_LOOKUP_LIMIT/g" /mnt/hdd/mynode/electrs/electrs.toml || true


# Remove old electrs data (pre-v9)
rm -rf /mnt/hdd/mynode/electrs/mainnet

# Install the electrs binary for this device. The overlay ships one binary per architecture,
# plus the older build used on devices that cannot run the current version (see
# ELECTRS_VERSION in mynode_app_versions.sh).
ELECTRS_DST=/usr/bin/electrs
ELECTRS_SRC=/usr/bin/electrs_arm32
case "$DEVICE_ARCH" in
    x86_64|amd64)
        ELECTRS_SRC=/usr/bin/electrs_amd64
        if [[ "$ELECTRS_VERSION" == v0.11.* ]]; then
            ELECTRS_SRC=/usr/bin/electrs_amd64_legacy
        fi
        ;;
    aarch64|arm64)
        ELECTRS_SRC=/usr/bin/electrs_arm64
        if [[ "$ELECTRS_VERSION" == v0.11.* ]]; then
            ELECTRS_SRC=/usr/bin/electrs_arm64_legacy
        fi
        ;;
esac
if [ -f "$ELECTRS_SRC" ]; then
    if ! cmp -s "$ELECTRS_SRC" "$ELECTRS_DST"; then
        echo "Installing electrs $ELECTRS_VERSION from $ELECTRS_SRC"
        cp -f "$ELECTRS_SRC" "$ELECTRS_DST"
        chmod 755 "$ELECTRS_DST"
    fi
else
    echo "WARNING: $ELECTRS_SRC is missing, keeping $ELECTRS_DST"
fi

# Remove an index the installed electrs cannot read. Neither case below is rebuilt by electrs
# on its own:
#  - v0.12 replaced the index ("Unsupported DB format (0 < 1)"), so an index built before v0.12
#    cannot be used by v0.12+, and the reverse.
#  - v0.11 moved to RocksDB 9, which v0.10 and older report as "unsupported format_version: 6".
#    v0.11 reads an index built by v0.10 and older.
# ELECTRS_INDEX_FORMAT_FILE records the electrs version (major.minor) that built the index on disk.
function version_at_least() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n 1)" = "$2" ]
}
function index_readable() {
    local built="$1" installed="$2"
    if version_at_least "$built" 0.12; then
        version_at_least "$installed" 0.12
    elif version_at_least "$installed" 0.12; then
        return 1
    elif version_at_least "$built" 0.11; then
        version_at_least "$installed" 0.11
    else
        return 0
    fi
}
function index_rocksdb_major() {
    local index_log="$1/LOG"
    if [ -f "$index_log" ]; then
        grep -m 1 -oE 'RocksDB version: [0-9]+' "$index_log" | grep -oE '[0-9]+$' || true
    fi
}

ELECTRS_INSTALLED_VERSION=$($ELECTRS_DST --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1) || true
if [ -n "$ELECTRS_INSTALLED_VERSION" ]; then
    INDEX_FORMAT=$(echo "$ELECTRS_INSTALLED_VERSION" | cut -d. -f1,2)
    INDEX_FORMAT_ON_DISK=""
    if [ -f $ELECTRS_INDEX_FORMAT_FILE ]; then
        INDEX_FORMAT_ON_DISK=$(cat $ELECTRS_INDEX_FORMAT_FILE)
    fi

    REMOVE_INDEX=0
    for INDEX_DIR in /mnt/hdd/mynode/electrs/bitcoin /mnt/hdd/mynode/electrs/testnet; do
        if [ ! -d $INDEX_DIR ]; then
            continue
        fi
        INDEX_BUILT_BY="$INDEX_FORMAT_ON_DISK"
        if [ -z "$INDEX_BUILT_BY" ]; then
            # No record of what built it, so ask RocksDB: v0.10 and older used RocksDB 7,
            # v0.11 uses RocksDB 9
            INDEX_BUILT_BY="0.10"
            ROCKSDB_MAJOR=$(index_rocksdb_major $INDEX_DIR)
            if [ -n "$ROCKSDB_MAJOR" ] && [ "$ROCKSDB_MAJOR" -ge 8 ]; then
                INDEX_BUILT_BY="0.11"
            fi
        fi
        if ! index_readable "$INDEX_BUILT_BY" "$INDEX_FORMAT"; then
            REMOVE_INDEX=1
        fi
    done

    # The checks above cannot catch every incompatibility, so recover from the ones that get
    # through: if the last run died reporting an index it could not read, remove the index
    # instead of restarting into the same error every RestartSec. Only format errors count - a
    # missing bitcoind or REST API must never trigger a rebuild. The reset file holds the time
    # of the last removal so the same errors are not acted on twice. Tracing is off around the
    # search because the traced command line would otherwise match itself on the next start.
    if [ $REMOVE_INDEX -eq 0 ] && [ -d /mnt/hdd/mynode/electrs/bitcoin ]; then
        set +x
        ELECTRS_DB_ERRORS="Unsupported DB format|unsupported format_version|re-index required"
        JOURNAL_SINCE=""
        LAST_RESET=$(cat $ELECTRS_INDEX_RESET_FILE 2>/dev/null) || true
        if [[ "$LAST_RESET" =~ ^[0-9]+$ ]]; then
            JOURNAL_SINCE="--since=@$LAST_RESET"
        fi
        if journalctl --unit=electrs --no-pager $JOURNAL_SINCE 2>/dev/null | grep -qE "$ELECTRS_DB_ERRORS"; then
            echo "The last electrs run exited on an index it could not read, so it will be rebuilt"
            REMOVE_INDEX=1
        fi
        unset ELECTRS_DB_ERRORS
        set -x
    fi

    if [ $REMOVE_INDEX -eq 1 ]; then
        echo "Removing the electrs index (built by ${INDEX_FORMAT_ON_DISK:-unknown}, installed electrs is $ELECTRS_INSTALLED_VERSION)"
        rm -rf /mnt/hdd/mynode/electrs/bitcoin /mnt/hdd/mynode/electrs/testnet
        date +%s > $ELECTRS_INDEX_RESET_FILE
    fi
    echo "$INDEX_FORMAT" > $ELECTRS_INDEX_FORMAT_FILE
fi

# v0.12+ reads blocks over the bitcoind REST API and exits with an HTTP 404 without it
if [[ "$ELECTRS_INSTALLED_VERSION" == 0.12.* ]]; then
    if ! grep -qE "^[[:space:]]*rest[[:space:]]*=[[:space:]]*1" /home/bitcoin/.bitcoin/bitcoin.conf 2>/dev/null; then
        echo "WARNING: rest=1 is missing from bitcoin.conf and electrs $ELECTRS_INSTALLED_VERSION cannot index without it"
    fi
fi

chown -R bitcoin:bitcoin /mnt/hdd/mynode/electrs

sync
sleep 3s