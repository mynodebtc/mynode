#!/bin/bash

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_functions.sh

set -x
set -e

# RTL config
sudo -u bitcoin mkdir -p /opt/mynode/RTL
sudo -u bitcoin mkdir -p /mnt/hdd/mynode/rtl
chown -R bitcoin:bitcoin /mnt/hdd/mynode/rtl
chown -R bitcoin:bitcoin /mnt/hdd/mynode/rtl_backup

# If local settings file is not a symlink, delete and setup symlink to HDD
if [ ! -L /opt/mynode/RTL/RTL-Config.json ]; then
    rm -f /opt/mynode/RTL/RTL-Config.json
    sudo -u bitcoin ln -s /mnt/hdd/mynode/rtl/RTL-Config.json /opt/mynode/RTL/RTL-Config.json
fi

RTL_CONFIG=/mnt/hdd/mynode/rtl/RTL-Config.json
# Hash of the last password MyNode set, so it can be told apart from one the user chose
SET_HASH_FILE=/mnt/hdd/mynode/rtl/.app_password_hash
APP_PASSWORD_FILE=/mnt/hdd/mynode/rtl/.app_password
# RTL's hash of "bolt", the password in MyNode's config template and the old MyNode default
BOLT_HASH="d0b3cba71f725563d316ea3516099328042095d10f4571be25c07f9ce31985a5"

# If config file on HDD does not exist, create it
if [ ! -f $RTL_CONFIG ]; then
    cp -f /usr/share/mynode/RTL-Config.json $RTL_CONFIG
fi

# Force update of RTL config file (increment to force new update)
RTL_CONFIG_UPDATE_NUM=1
if [ ! -f /mnt/hdd/mynode/rtl/update_settings_$RTL_CONFIG_UPDATE_NUM ]; then
    cp -f /usr/share/mynode/RTL-Config.json $RTL_CONFIG
    touch /mnt/hdd/mynode/rtl/update_settings_$RTL_CONFIG_UPDATE_NUM
fi

function set_generated_rtl_password() {
    RTL_PASSWORD=$(generate_app_password)
    export RTL_PASSWORD
    /usr/local/bin/python3 - <<'EOF'
import hashlib, os, re
path = "/mnt/hdd/mynode/rtl/RTL-Config.json"
digest = hashlib.sha256(os.environ["RTL_PASSWORD"].encode("utf-8")).hexdigest()
with open(path) as f:
    text = f.read()
text, count = re.subn(r'"multiPassHashed":.*', lambda m: '"multiPassHashed": "{}",'.format(digest), text)
if count == 0:
    raise SystemExit("multiPassHashed not found in " + path)
with open(path, "w") as f:
    f.write(text)
with open("/mnt/hdd/mynode/rtl/.app_password_hash", "w") as f:
    f.write(digest)
EOF
    save_app_default_password rtl "$RTL_PASSWORD"
    unset RTL_PASSWORD
}

set +x
CONFIG_HASH=$(sed -n 's/.*"multiPassHashed": *"\([^"]*\)".*/\1/p' $RTL_CONFIG)

# A password saved before the hash file existed was set by MyNode if it still matches the config
if [ ! -f $SET_HASH_FILE ] && has_app_password rtl && ! is_app_password_user_set rtl; then
    SAVED_HASH=$(printf '%s' "$(cat $APP_PASSWORD_FILE)" | sha256sum | cut -d' ' -f1)
    if [ "$SAVED_HASH" = "$CONFIG_HASH" ]; then
        printf '%s' "$CONFIG_HASH" > $SET_HASH_FILE
    fi
fi

if [ -z "$CONFIG_HASH" ] || [ "$CONFIG_HASH" = "$BOLT_HASH" ]; then
    # Fresh config, or still using the old default password
    set_generated_rtl_password
elif [ -f $SET_HASH_FILE ] && [ "$(cat $SET_HASH_FILE)" = "$CONFIG_HASH" ]; then
    # MyNode's own password, so replace it if it was cleared by a reinstall or reset
    if ! has_app_password rtl; then
        set_generated_rtl_password
    fi
else
    # The user changed the password inside RTL (or before MyNode generated passwords)
    save_app_password_user_set rtl
fi
set -x

# Update for testnet
if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
    sed -i "s/mainnet/testnet/g" /mnt/hdd/mynode/rtl/RTL-Config.json || true
else
    sed -i "s/testnet/mainnet/g" /mnt/hdd/mynode/rtl/RTL-Config.json || true
fi

# Update for loop connection
sed -i "s/localhost:8081/127.0.0.1:8081/g" /mnt/hdd/mynode/rtl/RTL-Config.json || true

sync
sleep 3s
