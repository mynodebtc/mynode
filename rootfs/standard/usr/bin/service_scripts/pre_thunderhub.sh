#!/bin/bash

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_functions.sh

set -x
set -e

# Thunderhub config
mkdir -p /mnt/hdd/mynode/thunderhub/
if [ ! -f /mnt/hdd/mynode/thunderhub/.env.local ]; then
    cp -f /usr/share/mynode/thunderhub.env /mnt/hdd/mynode/thunderhub/.env.local
fi

THUB_CONFIG=/mnt/hdd/mynode/thunderhub/thub_config.yaml
if [ ! -f $THUB_CONFIG ]; then
    cp -f /usr/share/mynode/thub_config.yaml $THUB_CONFIG
fi
THUNDERHUB_CONFIG_UPDATE_NUM=1
if [ ! -f /mnt/hdd/mynode/thunderhub/update_settings_$THUNDERHUB_CONFIG_UPDATE_NUM ]; then
    cp -f /usr/share/mynode/thunderhub.env /mnt/hdd/mynode/thunderhub/.env.local
    cp -f /usr/share/mynode/thub_config.yaml $THUB_CONFIG
    touch /mnt/hdd/mynode/thunderhub/update_settings_$THUNDERHUB_CONFIG_UPDATE_NUM
fi
if [ -f $THUB_CONFIG ]; then
    set +x
    # Work out whose master password is in the config: "default" (template or the old "bolt"
    # default), "mynode" (the last one MyNode set) or "user" (changed by the user)
    export APP_PASSWORD_USER_SET
    PASSWORD_OWNER=$(/usr/local/bin/python3 - <<'EOF'
import bcrypt, os, re
DIR = "/mnt/hdd/mynode/thunderhub/"
# Config value of the last password MyNode set
SET_HASH_FILE = DIR + ".app_password_hash"
PREFIX = "thunderhub-"

def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except FileNotFoundError:
        return None

def master_password(path):
    m = re.search(r"^masterPassword: *(['\"])(.*?)\1", read(path) or "", re.MULTILINE)
    return m.group(2) if m else ""

def verifies(password, value):
    if not value.startswith(PREFIX):
        return False
    try:
        return bcrypt.checkpw(password.encode("utf-8"), value[len(PREFIX):].encode("utf-8"))
    except ValueError:
        return False

value = master_password(DIR + "thub_config.yaml")
if value in ["", master_password("/usr/share/mynode/thub_config.yaml")] or verifies("bolt", value):
    print("default")
    raise SystemExit

set_value = read(SET_HASH_FILE)
saved = read(DIR + ".app_password")
# A password saved before the hash file existed was set by MyNode if it still matches the config
if set_value is None and saved and saved != os.environ["APP_PASSWORD_USER_SET"] and verifies(saved, value):
    with open(SET_HASH_FILE, "w") as f:
        f.write(value)
    set_value = value
print("mynode" if set_value == value else "user")
EOF
)
    if [ "$PASSWORD_OWNER" = "default" ] || { [ "$PASSWORD_OWNER" = "mynode" ] && ! has_app_password thunderhub; }; then
        # Fresh config or old default password, or MyNode's own password that was cleared by
        # a reinstall or reset
        THUNDERHUB_PASSWORD=$(generate_app_password)
        export THUNDERHUB_PASSWORD
        /usr/local/bin/python3 - <<'EOF'
import bcrypt, os, re
path = "/mnt/hdd/mynode/thunderhub/thub_config.yaml"
password_hash = bcrypt.hashpw(os.environ["THUNDERHUB_PASSWORD"].encode("utf-8"), bcrypt.gensalt()).decode("ascii")
master_password_value = "thunderhub-{}".format(password_hash)
with open(path) as f:
    text = f.read()
text, count = re.subn(r"^masterPassword:.*", "masterPassword: '{}'".format(master_password_value), text, flags=re.MULTILINE)
if count == 0:
    raise SystemExit("masterPassword not found in " + path)
with open(path, "w") as f:
    f.write(text)
with open("/mnt/hdd/mynode/thunderhub/.app_password_hash", "w") as f:
    f.write(master_password_value)
EOF
        save_app_default_password thunderhub "$THUNDERHUB_PASSWORD"
        unset THUNDERHUB_PASSWORD
    elif [ "$PASSWORD_OWNER" = "user" ]; then
        save_app_password_user_set thunderhub
    fi
    set -x

    if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
        sed -i "s/mainnet/testnet/g" /mnt/hdd/mynode/thunderhub/thub_config.yaml || true
    else
        sed -i "s/testnet/mainnet/g" /mnt/hdd/mynode/thunderhub/thub_config.yaml || true
    fi
fi

chown -R bitcoin:bitcoin /mnt/hdd/mynode/thunderhub

sync
sleep 3s
