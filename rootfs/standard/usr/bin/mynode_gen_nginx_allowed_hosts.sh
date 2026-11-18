#!/bin/bash

# Writes the host names nginx accepts for apps (see /etc/nginx/conf.d/mynode_allowed_hosts.conf):
# the same built-in names as get_builtin_hostnames() in device_info.py, plus the names added in
# Settings under Allowed Host Names. Run by nginx at start and by Settings when the list changes,
# followed by an nginx reload.

# The character ranges below must mean ASCII, whatever locale this runs under
export LC_ALL=C

OUT_FILE="/etc/nginx/mynode/mynode_allowed_host_names.conf"
ALLOWED_HOSTS_FILE="/mnt/hdd/mynode/settings/allowed_hosts"
LOCAL_HOST_SUFFIXES=("" ".local" ".lan" ".home" ".home.arpa" ".localdomain" ".internal")
LABEL="[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?"
HOSTNAME_REGEX="^${LABEL}(\.${LABEL})*$"
HOST_NAME="$(hostname | tr 'A-Z' 'a-z')"

list_builtin_names() {
    echo "localhost"
    # Docker containers, such as Jam, reach apps on the host by this name
    echo "host.docker.internal"
    for name in mynode "$HOST_NAME"; do
        for suffix in "${LOCAL_HOST_SUFFIXES[@]}"; do
            echo "${name}${suffix}"
        done
    done
}

list_added_names() {
    if [ -f "$ALLOWED_HOSTS_FILE" ]; then
        cat "$ALLOWED_HOSTS_FILE"
    fi
}

# Same rules as normalize_hostname() and is_valid_hostname(). Anything else is left out, so a
# hand-edited line cannot break the nginx config, and grep -a keeps a stray binary byte from
# dropping every line. Names are written as anchored regexes rather than exact keys, since nginx
# fails to start when an exact key is longer than map_hash_bucket_size.
write_names() {
    tr 'A-Z' 'a-z' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\.$//' \
        | grep -a -E "$HOSTNAME_REGEX" | awk 'length($0) <= 253' | sort -u \
        | sed -e 's/\./\\./g' -e 's/^/~^/' -e 's/$/$ 1;/'

    # With several devices on one network, Avahi publishes all but the first as mynode-2.local,
    # mynode-3.local and so on, and can rename the device at any time after boot
    for name in mynode "$HOST_NAME"; do
        if echo "$name" | grep -qxE "$LABEL"; then
            echo "~^${name}-[0-9]+\\.local\$ 1;"
        fi
    done | sort -u
}

write_file() {
    mkdir -p "$(dirname "$OUT_FILE")"
    TMP_FILE="$(mktemp "${OUT_FILE}.XXXXXX")" || exit 1
    "$@" | write_names > "$TMP_FILE"
    chmod 644 "$TMP_FILE"
    # The temporary name does not match the include pattern, so nginx never reads a partial file
    mv -f "$TMP_FILE" "$OUT_FILE"
}

list_all_names() {
    list_builtin_names
    list_added_names
}

config_ok() {
    /usr/sbin/nginx -t -q -g 'daemon on; master_process on;' > /dev/null 2>&1
}

write_file list_all_names

# Never let the names stop nginx from starting. If the config only passes without the added
# names, leave them out; if it fails either way, the names are not the cause, so keep them all.
if ! config_ok; then
    write_file list_builtin_names
    if config_ok; then
        echo "nginx config test failed with the added host names; using the built-in names only" >&2
    else
        write_file list_all_names
    fi
fi
