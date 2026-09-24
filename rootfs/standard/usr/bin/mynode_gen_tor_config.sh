#!/bin/bash

# Enables or disables the MyNode tor hidden services in /etc/torrc.d.
#
# Disabled services stay on disk with every line prefixed by the marker below, so
# enabling them again restores the exact same config (and the same .onion address,
# since the keys in /var/lib/tor are never touched).
#
# Tor only creates a service's keys when it publishes the service, so keys for
# disabled services are created here by an offline tor instance. That gives every
# service an onion name from the start, for TLS certificates and for enabling later.
#
# Usage:
#   mynode_gen_tor_config.sh             Update every file in /etc/torrc.d
#   mynode_gen_tor_config.sh <name>...   Update only the named file(s)

TORRC_DIR=/etc/torrc.d
MARKER="#DISABLED# "

mkdir -p $TORRC_DIR

is_remote_access_disabled() {
    if [ -f /mnt/hdd/mynode/settings/tor_remote_access_disabled ] || [ -f /home/bitcoin/.mynode/tor_remote_access_disabled ]; then
        return 0
    fi
    return 1
}

# Comment out every line that is not already commented out. The entire block must be
# commented, not just HiddenServiceDir - tor attaches HiddenServicePort lines to the
# most recent HiddenServiceDir, so a lone HiddenServiceDir comment would move this
# service's ports onto the previous service.
disable_torrc_file() {
    sed -i "/^${MARKER}/! s/^/${MARKER}/" "$1"
}

enable_torrc_file() {
    sed -i "s/^${MARKER}//" "$1"
}

# Print the hidden service folders in a torrc file that do not have keys yet
get_missing_onion_dirs() {
    sed -n "s/^\(${MARKER}\)\{0,1\}HiddenServiceDir[[:space:]]\{1,\}\([^[:space:]]*\).*/\2/p" "$1" | while read -r dir; do
        if [ ! -f "${dir%/}/hostname" ]; then
            echo "$dir"
        fi
    done
}

# Create keys for the given hidden service folders without publishing them.
# DisableNetwork keeps this tor instance from making any connection at all.
create_onion_keys() {
    if [ $# -eq 0 ] || ! command -v tor > /dev/null; then
        return
    fi

    local keygen_dir=$(mktemp -d)
    chown debian-tor:debian-tor $keygen_dir
    chmod 700 $keygen_dir
    {
        echo "DataDirectory $keygen_dir/data"
        echo "SocksPort 0"
        echo "ControlPort 0"
        echo "DisableNetwork 1"
        for dir in "$@"; do
            echo "HiddenServiceDir $dir"
            echo "HiddenServicePort 1 127.0.0.1:1"
        done
    } > $keygen_dir/torrc

    timeout 60 runuser -u debian-tor -- tor --defaults-torrc /dev/null -f $keygen_dir/torrc > /dev/null 2>&1 &
    local keygen_pid=$!

    # Keys are written during startup, so stop as soon as every hostname exists
    for i in $(seq 1 120); do
        local all_created=1
        for dir in "$@"; do
            if [ ! -f "${dir%/}/hostname" ]; then
                all_created=0
            fi
        done
        if [ $all_created -eq 1 ] || ! kill -0 $keygen_pid 2> /dev/null; then
            break
        fi
        sleep 0.5
    done

    kill $keygen_pid 2> /dev/null
    wait $keygen_pid 2> /dev/null
    rm -rf $keygen_dir
}

FILES=""
if [ $# -gt 0 ]; then
    for name in "$@"; do
        FILES="$FILES $TORRC_DIR/$(basename $name)"
    done
else
    FILES=$TORRC_DIR/*
fi

MISSING_ONION_DIRS=""
for f in $FILES; do
    if [ ! -f "$f" ]; then
        continue
    fi

    if is_remote_access_disabled; then
        disable_torrc_file "$f"
        MISSING_ONION_DIRS="$MISSING_ONION_DIRS $(get_missing_onion_dirs "$f")"
    else
        enable_torrc_file "$f"
    fi
done

create_onion_keys $MISSING_ONION_DIRS

sync
