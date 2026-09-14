#!/bin/bash

# This will run prior to launching the application

source /usr/share/mynode/mynode_functions.sh

# Set the login password the first time LNDBoss starts after an install or reinstall.
# After that the user may change it inside LNDBoss.
AUTH_FILE=/mnt/hdd/mynode/lndboss/auth.json
if ! has_app_password lndboss || ! grep -q passwordHash $AUTH_FILE 2>/dev/null; then
    LNDBOSS_PASSWORD=$(generate_app_password) || exit 1
    export LNDBOSS_PASSWORD
    /usr/local/bin/python3 - <<'EOF' || exit 1
import bcrypt, json, os
password_hash = bcrypt.hashpw(os.environ["LNDBOSS_PASSWORD"].encode("utf-8"), bcrypt.gensalt()).decode("ascii")
with open(os.open("/mnt/hdd/mynode/lndboss/auth.json", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
    json.dump({"username": "admin", "passwordHash": password_hash}, f, indent=2)
os.chmod("/mnt/hdd/mynode/lndboss/auth.json", 0o600)
EOF
    save_app_password lndboss "$LNDBOSS_PASSWORD"
    unset LNDBOSS_PASSWORD
fi

mkdir -p /mnt/hdd/mynode/lndboss/local
cat << EOF > /mnt/hdd/mynode/lndboss/config.json
{
  "default_saved_node": "local"
}
EOF
cat << EOF > /mnt/hdd/mynode/lndboss/local/credentials.json
{
  "cert_path": "/.lnd/tls.cert",
  "macaroon_path": "/.lnd/data/chain/bitcoin/mainnet/admin.macaroon",
  "socket": "host.docker.internal:10009"
}
EOF


# Create env file
MY_UID=$(id -u)
MY_GID=$(id -g)
echo "UID=$MY_UID" >  /mnt/hdd/mynode/lndboss/env
echo "GID=$MY_GID" >> /mnt/hdd/mynode/lndboss/env
