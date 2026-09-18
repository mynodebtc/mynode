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
# Reset Configuration replaces config.json with MyNode's template, which has no login. Turn
# password login back on with the existing admin password, which the app page shows or the
# user knows. A missing or default admin password gets a new one below instead.
if has_app_password specter; then
    /usr/local/bin/python3 - <<'EOF'
import binascii, hashlib, json, os, sys

SPECTER_DIR = "/mnt/hdd/mynode/specter"
CONFIG_FILE = SPECTER_DIR + "/config.json"
USERS_FILE = SPECTER_DIR + "/users.json"
NEEDS_NEW_PASSWORD = 3

def verify_password(stored, password):
    pwdhash = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), stored["salt"].encode(), 10000)
    return pwdhash == binascii.a2b_base64(stored["pwdhash"])

config = json.load(open(CONFIG_FILE))
auth = config.get("auth", {})
if auth.get("method", "none") != "none":
    sys.exit(0)
users = json.load(open(USERS_FILE)) if os.path.isfile(USERS_FILE) else []
admin = next((u for u in users if u.get("id") == "admin"), None)
if admin is None or verify_password(admin["password"], "admin"):
    sys.exit(NEEDS_NEW_PASSWORD)
auth["method"] = "passwordonly"
config["auth"] = auth
with open(os.open(CONFIG_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
    json.dump(config, f, indent=4)
EOF
    RESULT=$?
    if [ $RESULT -eq 3 ]; then
        rm -f /mnt/hdd/mynode/specter/.app_password
    elif [ $RESULT -ne 0 ]; then
        exit 1
    fi
fi

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

# Only replace a password that is not the user's own
set_by_mynode = os.path.isfile(SET_HASH_FILE) and json.load(open(SET_HASH_FILE)) == admin["password"]
not_users_own = auth.get("method", "none") == "none" or set_by_mynode or verify_password(admin["password"], SPECTER_DEFAULT_PASSWORD)
if not not_users_own:
    sys.exit(SKIPPED)

admin["password"] = hash_password(os.environ["SPECTER_PASSWORD"])
admin["encrypted_user_secret"] = None   # Specter makes a new one at the next login
# Service data (only Swan's login and auto-withdrawal settings) is encrypted with the secret
# discarded above and could no longer be read, so remove it. The user reconnects the service.
admin["services"] = []
try:
    os.remove("{}/{}_services.json".format(SPECTER_DIR, admin.get("username", "admin")))
except FileNotFoundError:
    pass
auth["method"] = "passwordonly"
config["auth"] = auth
write_json(USERS_FILE, users)
write_json(CONFIG_FILE, config)
write_json(SET_HASH_FILE, admin["password"])
EOF
    RESULT=$?
    if [ $RESULT -eq 0 ]; then
        save_app_default_password specter "$SPECTER_PASSWORD"
    elif [ $RESULT -eq 3 ]; then
        # Admin password is the user's own, so it was left alone. Record that, so the app
        # page doesn't show a stale or blank password.
        save_app_password_user_set specter
    else
        exit 1
    fi
    unset SPECTER_PASSWORD
elif ! is_app_password_user_set specter; then
    # Once the user changes the password inside Specter, it is no longer MyNode's
    /usr/local/bin/python3 - <<'EOF'
import json, sys

SPECTER_DIR = "/mnt/hdd/mynode/specter"
CHANGED = 3

try:
    users = json.load(open(SPECTER_DIR + "/users.json"))
    set_hash = json.load(open(SPECTER_DIR + "/.app_password_hash"))
except (FileNotFoundError, ValueError):
    sys.exit(0)
admin = next((u for u in users if u.get("id") == "admin"), None)
if admin is None or admin.get("password") != set_hash:
    sys.exit(CHANGED)
EOF
    if [ $? -eq 3 ]; then
        save_app_password_user_set specter
    fi
fi
set -x
