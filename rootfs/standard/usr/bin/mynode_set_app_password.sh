#!/bin/bash

# Set a custom login password for an app from Settings.
# Usage: mynode_set_app_password.sh <rtl|thunderhub|lndg|lndboss|specter>   (new password read from stdin)

source /usr/share/mynode/mynode_functions.sh

set -e

APP="$1"
IFS= read -r PASSWORD

if [ -z "$PASSWORD" ]; then
    echo "ERROR: No password given. Password not changed."
    exit 1
fi

# The user already knows this password, so unlike a generated one it is not saved for the app
# page to show; the page shows it as user configured instead.
case "$APP" in
    rtl)
        export RTL_PASSWORD="$PASSWORD"
        /usr/bin/mynode-python - <<'EOF'
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
        save_app_password_user_set rtl
        unset RTL_PASSWORD
        chown -R bitcoin:bitcoin /mnt/hdd/mynode/rtl
        systemctl try-restart --no-block rtl
        ;;
    thunderhub)
        export THUNDERHUB_PASSWORD="$PASSWORD"
        /usr/bin/mynode-python - <<'EOF'
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
EOF
        save_app_password_user_set thunderhub
        unset THUNDERHUB_PASSWORD
        chown -R bitcoin:bitcoin /mnt/hdd/mynode/thunderhub
        systemctl try-restart --no-block thunderhub
        ;;
    lndg)
        # Run as LNDg's own user, with the password on stdin
        cd /opt/mynode/lndg
        printf '%s' "$PASSWORD" | sudo -u lndg .venv/bin/python manage.py shell -c "
import sys
from django.contrib.auth import get_user_model
admin = get_user_model().objects.get(username='admin')
admin.set_password(sys.stdin.read())
admin.save()
"
        save_app_password_user_set lndg
        ;;
    lndboss)
        # LndBoss reads auth.json at each login, so no restart is needed
        export LNDBOSS_PASSWORD="$PASSWORD"
        /usr/bin/mynode-python - <<'EOF'
import bcrypt, json, os
path = "/mnt/hdd/mynode/lndboss/auth.json"
try:
    with open(path) as f:
        username = json.load(f).get("username") or "admin"
except (FileNotFoundError, ValueError, AttributeError):
    username = "admin"
password_hash = bcrypt.hashpw(os.environ["LNDBOSS_PASSWORD"].encode("utf-8"), bcrypt.gensalt()).decode("ascii")
with open(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
    json.dump({"username": username, "passwordHash": password_hash}, f, indent=2)
os.chmod(path, 0o600)
EOF
        chown bitcoin:bitcoin /mnt/hdd/mynode/lndboss/auth.json
        save_app_password_user_set lndboss
        unset LNDBOSS_PASSWORD
        ;;
    specter)
        # Specter keeps users in memory and writes users.json itself, so stop it while the
        # file is changed, and start it again even if the change fails
        systemctl stop specter
        trap 'rc=$?; systemctl is-enabled --quiet specter && systemctl start --no-block specter || true; exit $rc' EXIT
        if [ ! -f /mnt/hdd/mynode/specter/config.json ]; then
            cp -f /usr/share/mynode/specter.conf /mnt/hdd/mynode/specter/config.json
        fi
        export SPECTER_PASSWORD="$PASSWORD"
        /usr/bin/mynode-python - <<'EOF'
import binascii, hashlib, json, os

SPECTER_DIR = "/mnt/hdd/mynode/specter"
CONFIG_FILE = SPECTER_DIR + "/config.json"
USERS_FILE = SPECTER_DIR + "/users.json"

# Same format as hash_password() in Specter's user.py (and pre_specter.sh)
def hash_password(password):
    salt = binascii.b2a_base64(hashlib.sha256(os.urandom(60)).digest()).strip()
    pwdhash = binascii.b2a_base64(hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 10000)).strip().decode()
    return {"salt": salt.decode(), "pwdhash": pwdhash}

def write_json(path, data):
    with open(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        json.dump(data, f, indent=4)
    os.chmod(path, 0o600)

config = json.load(open(CONFIG_FILE))
users = json.load(open(USERS_FILE)) if os.path.isfile(USERS_FILE) else []
admin = next((u for u in users if u.get("id") == "admin"), None)
if admin is None:
    # What Specter creates on its first start, see load_users() in Specter's user_manager.py
    admin = {"id": "admin", "username": "admin", "is_admin": True}
    users.insert(0, admin)
admin["password"] = hash_password(os.environ["SPECTER_PASSWORD"])
admin["encrypted_user_secret"] = None   # Specter makes a new one at the next login
# Service data (only Swan's login and auto-withdrawal settings) is encrypted with the secret
# discarded above and could no longer be read, so remove it. The user reconnects the service.
admin["services"] = []
try:
    os.remove("{}/{}_services.json".format(SPECTER_DIR, admin.get("username", "admin")))
except FileNotFoundError:
    pass
auth = config.get("auth", {})
auth["method"] = "passwordonly"
config["auth"] = auth
write_json(USERS_FILE, users)
write_json(CONFIG_FILE, config)
EOF
        unset SPECTER_PASSWORD
        chown bitcoin:bitcoin /mnt/hdd/mynode/specter/config.json /mnt/hdd/mynode/specter/users.json
        save_app_password_user_set specter
        ;;
    *)
        echo "ERROR: Unsupported app: $APP"
        exit 1
        ;;
esac
