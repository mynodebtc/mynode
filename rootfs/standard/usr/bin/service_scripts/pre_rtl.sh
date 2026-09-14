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

# If config file on HDD does not exist, create it
if [ ! -f /mnt/hdd/mynode/rtl/RTL-Config.json ]; then
    cp -f /usr/share/mynode/RTL-Config.json /mnt/hdd/mynode/rtl/RTL-Config.json
    rm -f /mnt/hdd/mynode/rtl/.app_password
fi

# Force update of RTL config file (increment to force new update)
RTL_CONFIG_UPDATE_NUM=1
if [ ! -f /mnt/hdd/mynode/rtl/update_settings_$RTL_CONFIG_UPDATE_NUM ]; then
    cp -f /usr/share/mynode/RTL-Config.json /mnt/hdd/mynode/rtl/RTL-Config.json
    rm -f /mnt/hdd/mynode/rtl/.app_password
    touch /mnt/hdd/mynode/rtl/update_settings_$RTL_CONFIG_UPDATE_NUM
fi

# Set the login password the first time RTL starts with a fresh config.
# After that the user may change it inside RTL.
set +x
if ! has_app_password rtl; then
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
EOF
    save_app_password rtl "$RTL_PASSWORD"
    unset RTL_PASSWORD
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
