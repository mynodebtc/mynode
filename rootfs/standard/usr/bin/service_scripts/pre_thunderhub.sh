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
if [ ! -f /mnt/hdd/mynode/thunderhub/thub_config.yaml ]; then
    cp -f /usr/share/mynode/thub_config.yaml /mnt/hdd/mynode/thunderhub/thub_config.yaml
    rm -f /mnt/hdd/mynode/thunderhub/.app_password
fi
THUNDERHUB_CONFIG_UPDATE_NUM=1
if [ ! -f /mnt/hdd/mynode/thunderhub/update_settings_$THUNDERHUB_CONFIG_UPDATE_NUM ]; then
    cp -f /usr/share/mynode/thunderhub.env /mnt/hdd/mynode/thunderhub/.env.local
    cp -f /usr/share/mynode/thub_config.yaml /mnt/hdd/mynode/thunderhub/thub_config.yaml
    rm -f /mnt/hdd/mynode/thunderhub/.app_password
    touch /mnt/hdd/mynode/thunderhub/update_settings_$THUNDERHUB_CONFIG_UPDATE_NUM
fi
if [ -f /mnt/hdd/mynode/thunderhub/thub_config.yaml ]; then
    # Set the master password the first time Thunderhub starts with a fresh config.
    # After that the user may change it in the Thunderhub config.
    set +x
    if ! has_app_password thunderhub; then
        THUNDERHUB_PASSWORD=$(generate_app_password)
        export THUNDERHUB_PASSWORD
        /usr/local/bin/python3 - <<'EOF'
import bcrypt, os, re
path = "/mnt/hdd/mynode/thunderhub/thub_config.yaml"
password_hash = bcrypt.hashpw(os.environ["THUNDERHUB_PASSWORD"].encode("utf-8"), bcrypt.gensalt()).decode("ascii")
with open(path) as f:
    text = f.read()
text, count = re.subn(r'masterPassword:.*', lambda m: 'masterPassword: "thunderhub-{}"'.format(password_hash), text)
if count == 0:
    raise SystemExit("masterPassword not found in " + path)
with open(path, "w") as f:
    f.write(text)
EOF
        save_app_password thunderhub "$THUNDERHUB_PASSWORD"
        unset THUNDERHUB_PASSWORD
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
