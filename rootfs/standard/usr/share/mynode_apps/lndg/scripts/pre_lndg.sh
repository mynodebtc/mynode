#!/bin/bash

source /usr/share/mynode/mynode_functions.sh

set -e

# Work out whose admin password is in the LNDg database: "default" (the old "bolt" default),
# "mynode" (the last one MyNode set), "unknown" (never tracked, e.g. the random one LNDg sets
# on a fresh install) or "user" (set from the MyNode settings page)
export APP_PASSWORD_USER_SET
PASSWORD_OWNER=$(/usr/local/bin/python3 - <<'EOF'
import base64, hashlib, hmac, os, sqlite3
DIR = "/mnt/hdd/mynode/lndg/"
# Django hash of the last password MyNode set
SET_HASH_FILE = DIR + ".app_password_hash"

def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except FileNotFoundError:
        return None

db = sqlite3.connect("file:" + DIR + "data/db.sqlite3?mode=ro", uri=True)
row = db.execute("SELECT password FROM auth_user WHERE username = 'admin'").fetchone()
value = row[0] if row else ""

# Same check as Django's PBKDF2PasswordHasher, which LNDg uses
def verifies(password):
    try:
        algorithm, iterations, salt, digest = value.split("$", 3)
        if algorithm != "pbkdf2_sha256":
            return False
        computed = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), int(iterations))
    except ValueError:
        return False
    return hmac.compare_digest(base64.b64encode(computed).decode("ascii"), digest)

if verifies("bolt"):
    print("default")
    raise SystemExit

set_value = read(SET_HASH_FILE)
saved = read(DIR + ".app_password")
# A password saved before the hash file existed was set by MyNode if it still matches the database
if set_value is None and saved and saved != os.environ["APP_PASSWORD_USER_SET"] and verifies(saved):
    with open(SET_HASH_FILE, "w") as f:
        f.write(value)
    set_value = value
if set_value is None:
    # Untracked, unless it was set from the settings page before MyNode tracked one
    print("user" if saved == os.environ["APP_PASSWORD_USER_SET"] else "unknown")
else:
    print("mynode" if set_value == value else "user")
EOF
)

if [ "$PASSWORD_OWNER" = "default" ] || [ "$PASSWORD_OWNER" = "unknown" ] || \
   { [ "$PASSWORD_OWNER" = "mynode" ] && ! has_app_password lndg; }; then
    # Old default or a password nobody was shown, or MyNode's own password that was cleared
    # by a reinstall or reset
    LNDG_ADMIN_PASSWORD=$(generate_app_password)
    export LNDG_ADMIN_PASSWORD
    cd /opt/mynode/lndg
    .venv/bin/python manage.py shell -c "
import os
from django.contrib.auth import get_user_model
admin = get_user_model().objects.get(username='admin')
admin.set_password(os.environ['LNDG_ADMIN_PASSWORD'])
admin.save()
with open('/mnt/hdd/mynode/lndg/.app_password_hash', 'w') as f:
    f.write(admin.password)
"
    save_app_default_password lndg "$LNDG_ADMIN_PASSWORD"
    unset LNDG_ADMIN_PASSWORD
elif [ "$PASSWORD_OWNER" = "user" ]; then
    save_app_password_user_set lndg
fi
