#!/bin/bash

# Makes the Redis password the first time (see the include at the end of /etc/redis/redis.conf) and
# writes LndHub's config with it. Run as root before Redis and LndHub start.

# The character ranges below must mean ASCII, whatever locale this runs under
export LC_ALL=C

PASSWORD_CONF="/etc/redis/mynode_redis_password.conf"
LNDHUB_FOLDER="/opt/mynode/LndHub"
LNDHUB_CONFIG_TEMPLATE="/usr/share/mynode/lndhub-config.js"

# Redis and LndHub can start at the same time; only one of them may make the password
exec 9> /run/lock/mynode_redis_password.lock
flock 9

umask 077
mkdir -p "$(dirname "$PASSWORD_CONF")"

password=""
if [ -f "$PASSWORD_CONF" ]; then
    password="$(sed -n 's/^requirepass \([A-Za-z0-9]\{32,\}\)$/\1/p' "$PASSWORD_CONF" | head -n 1)"
fi
if [ -z "$password" ]; then
    password="$(< /dev/urandom tr -dc A-Za-z0-9 | head -c 48)"
    TMP_FILE="$(mktemp "${PASSWORD_CONF}.XXXXXX")" || exit 1
    echo "requirepass $password" > "$TMP_FILE"
    chown redis:redis "$TMP_FILE"
    chmod 600 "$TMP_FILE"
    mv -f "$TMP_FILE" "$PASSWORD_CONF"
fi

if [ -d "$LNDHUB_FOLDER" ]; then
    TMP_FILE="$(mktemp "${LNDHUB_FOLDER}/config.js.XXXXXX")" || exit 1
    # The password goes to sed on stdin, since command lines are visible to every user
    printf 's/MYNODE_REDIS_PASSWORD/%s/\n' "$password" | sed -f - "$LNDHUB_CONFIG_TEMPLATE" > "$TMP_FILE"
    chown bitcoin:bitcoin "$TMP_FILE"
    chmod 600 "$TMP_FILE"
    mv -f "$TMP_FILE" "$LNDHUB_FOLDER/config.js"
fi
