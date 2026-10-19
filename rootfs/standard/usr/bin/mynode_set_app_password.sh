#!/bin/bash

# Set a custom login password for an app from Settings.
# Usage: mynode_set_app_password.sh <rtl|thunderhub|lndg|lndboss>   (new password read from stdin)

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
    *)
        echo "ERROR: Unsupported app: $APP"
        exit 1
        ;;
esac
