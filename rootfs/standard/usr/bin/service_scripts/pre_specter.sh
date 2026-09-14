#!/bin/bash

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_functions.sh

set -x

if [ ! -f /mnt/hdd/mynode/specter/config.json ]; then
    cp -f /usr/share/mynode/specter.conf /mnt/hdd/mynode/specter/config.json
fi

# Turn on password login with a generated password the first time Specter starts after an
# install or reinstall. A password the user set up themselves is left alone.
set +x
if ! has_app_password specter; then
    SPECTER_PASSWORD=$(generate_app_password) || exit 1
    export SPECTER_PASSWORD
    /usr/local/bin/python3 - <<'EOF'
import binascii, hashlib, json, os, sys

SPECTER_DIR = "/mnt/hdd/mynode/specter"
CONFIG_FILE = SPECTER_DIR + "/config.json"
USERS_FILE = SPECTER_DIR + "/users.json"
# Hash of the last password MyNode set, so a reinstall can tell it apart from one the user chose
SET_HASH_FILE = SPECTER_DIR + "/.app_password_hash"
SPECTER_DEFAULT_PASSWORD = "admin"
SKIPPED = 3

# Same format as hash_password() and verify_password() in Specter's user.py
def hash_password(password):
    salt = binascii.b2a_base64(hashlib.sha256(os.urandom(60)).digest()).strip()
    pwdhash = binascii.b2a_base64(hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 10000)).strip().decode()
    return {"salt": salt.decode(), "pwdhash": pwdhash}

def verify_password(stored, password):
    pwdhash = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), stored["salt"].encode(), 10000)
    return pwdhash == binascii.a2b_base64(stored["pwdhash"])

def write_json(path, data):
    with open(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        json.dump(data, f, indent=4)
    os.chmod(path, 0o600)

config = json.load(open(CONFIG_FILE))
auth = config.get("auth", {})
if os.path.isfile(USERS_FILE):
    users = json.load(open(USERS_FILE))
else:
    # What Specter creates on its first start, see load_users() in Specter's user_manager.py
    users = [{"id": "admin", "username": "admin", "password": hash_password(SPECTER_DEFAULT_PASSWORD), "is_admin": True, "encrypted_user_secret": None}]
admin = next((u for u in users if u.get("id") == "admin"), None)
if admin is None:
    sys.exit(SKIPPED)

# Replacing the password also discards the admin's encrypted user secret, which protects
# any configured services, so only replace a password that is not the user's own.
set_by_mynode = os.path.isfile(SET_HASH_FILE) and json.load(open(SET_HASH_FILE)) == admin["password"]
not_users_own = auth.get("method", "none") == "none" or set_by_mynode or verify_password(admin["password"], SPECTER_DEFAULT_PASSWORD)
if admin.get("services") or not not_users_own:
    sys.exit(SKIPPED)

admin["password"] = hash_password(os.environ["SPECTER_PASSWORD"])
admin["encrypted_user_secret"] = None   # Specter makes a new one at the next login
auth["method"] = "passwordonly"
config["auth"] = auth
write_json(USERS_FILE, users)
write_json(CONFIG_FILE, config)
write_json(SET_HASH_FILE, admin["password"])
EOF
    RESULT=$?
    if [ $RESULT -eq 0 ]; then
        save_app_password specter "$SPECTER_PASSWORD"
    elif [ $RESULT -ne 3 ]; then
        exit 1
    fi
    unset SPECTER_PASSWORD
fi
set -x
