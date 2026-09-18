#!/bin/bash

# This will run prior to launching the application

source /usr/share/mynode/mynode_functions.sh

# Work out whose login password is in auth.json: "default" (none, or the old "bolt" default),
# "mynode" (the last one MyNode set) or "user" (set before MyNode generated passwords)
export APP_PASSWORD_USER_SET
PASSWORD_OWNER=$(/usr/local/bin/python3 - <<'EOF'
import bcrypt, json, os
DIR = "/mnt/hdd/mynode/lndboss/"
# passwordHash of the last password MyNode set
SET_HASH_FILE = DIR + ".app_password_hash"

def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except FileNotFoundError:
        return None

try:
    value = json.loads(read(DIR + "auth.json") or "").get("passwordHash") or ""
except (ValueError, AttributeError):
    value = ""

def verifies(password):
    try:
        return bcrypt.checkpw(password.encode("utf-8"), value.encode("utf-8"))
    except ValueError:
        return False

if value == "" or verifies("bolt"):
    print("default")
    raise SystemExit

set_value = read(SET_HASH_FILE)
saved = read(DIR + ".app_password")
# A password saved before the hash file existed was set by MyNode if it still matches auth.json
if set_value is None and saved and saved != os.environ["APP_PASSWORD_USER_SET"] and verifies(saved):
    with open(SET_HASH_FILE, "w") as f:
        f.write(value)
    set_value = value
print("mynode" if set_value == value else "user")
EOF
) || exit 1

if [ "$PASSWORD_OWNER" = "default" ] || { [ "$PASSWORD_OWNER" = "mynode" ] && ! has_app_password lndboss; }; then
    # No password yet or old default password, or MyNode's own password that was cleared by
    # a reinstall or reset
    LNDBOSS_PASSWORD=$(generate_app_password) || exit 1
    export LNDBOSS_PASSWORD
    /usr/local/bin/python3 - <<'EOF' || exit 1
import bcrypt, json, os
password_hash = bcrypt.hashpw(os.environ["LNDBOSS_PASSWORD"].encode("utf-8"), bcrypt.gensalt()).decode("ascii")
with open(os.open("/mnt/hdd/mynode/lndboss/auth.json", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
    json.dump({"username": "admin", "passwordHash": password_hash}, f, indent=2)
os.chmod("/mnt/hdd/mynode/lndboss/auth.json", 0o600)
with open("/mnt/hdd/mynode/lndboss/.app_password_hash", "w") as f:
    f.write(password_hash)
EOF
    save_app_default_password lndboss "$LNDBOSS_PASSWORD"
    unset LNDBOSS_PASSWORD
elif [ "$PASSWORD_OWNER" = "user" ]; then
    save_app_password_user_set lndboss
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
