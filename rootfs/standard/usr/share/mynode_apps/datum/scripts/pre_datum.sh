#!/bin/bash

# This will run prior to launching the application

source /usr/share/mynode/mynode_functions.sh

set -e

DATUM_CONFIG=/mnt/hdd/mynode/datum/datum_config.json
# Hash of the last password MyNode set, so it can be told apart from one the user chose
SET_HASH_FILE=/mnt/hdd/mynode/datum/.app_password_hash

function set_generated_datum_password() {
    DATUM_ADMIN_PASSWORD=$(generate_app_password)
    export DATUM_ADMIN_PASSWORD
    (umask 077
     jq '.api.admin_password = env.DATUM_ADMIN_PASSWORD' $DATUM_CONFIG > $DATUM_CONFIG.tmp
     mv $DATUM_CONFIG.tmp $DATUM_CONFIG
     printf '%s' "$DATUM_ADMIN_PASSWORD" | sha256sum | cut -d' ' -f1 > $SET_HASH_FILE)
    save_app_default_password datum "$DATUM_ADMIN_PASSWORD"
    unset DATUM_ADMIN_PASSWORD
}

if [ -f $DATUM_CONFIG ]; then
    CONFIG_PASSWORD=$(jq -r '.api.admin_password // ""' $DATUM_CONFIG)
    CONFIG_HASH=$(printf '%s' "$CONFIG_PASSWORD" | sha256sum | cut -d' ' -f1)

    # A password saved before the hash file existed was set by MyNode if it still matches the config
    if [ ! -f $SET_HASH_FILE ] && has_app_password datum && ! is_app_password_user_set datum && \
       [ "$(cat /mnt/hdd/mynode/datum/.app_password)" = "$CONFIG_PASSWORD" ]; then
        (umask 077; printf '%s\n' "$CONFIG_HASH" > $SET_HASH_FILE)
    fi

    if [ -z "$CONFIG_PASSWORD" ] || [ "$CONFIG_PASSWORD" = "bolt" ]; then
        # Fresh config, or still using the old default password
        set_generated_datum_password
    elif [ -f $SET_HASH_FILE ] && [ "$(cat $SET_HASH_FILE)" = "$CONFIG_HASH" ]; then
        # MyNode's own password, so replace it if it was cleared by a reinstall or reset
        if ! has_app_password datum; then
            set_generated_datum_password
        fi
    else
        # The user changed the password in the DATUM config
        save_app_password_user_set datum
    fi
fi
