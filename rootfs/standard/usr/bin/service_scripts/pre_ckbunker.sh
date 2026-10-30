#!/bin/bash

source /usr/share/mynode/mynode_functions.sh

set -e

# Listen on 127.0.0.1:19823 only. nginx serves PORT_NUMBER (9823, HTTP) and 9824 (HTTPS) behind the
# MyNode login, and CKBunker's own onion service, which points at PORT_NUMBER, goes through it too.
sed -i -e "s/web._run_app(app, port=settings.PORT_NUMBER/web._run_app(app, host='127.0.0.1', port=19823/" \
    -e "s/web._run_app(app, host='127.0.0.1', port=settings.PORT_NUMBER/web._run_app(app, host='127.0.0.1', port=19823/" \
    /opt/mynode/ckbunker/webapp.py

# Set the master login password the first time CKBunker starts with MyNode's settings file.
# A password saved in the CKBunker Bunker Setup tab takes precedence over this one.
SETTINGS_FILE=/mnt/hdd/mynode/ckbunker/settings.yaml

# Once a Coldcard has been set up, CKBunker keeps its own copy of the password it had then, in
# bunker settings encrypted with a key from the Coldcard (bp-*.dat), and uses that copy instead.
# MyNode can't read or change it, so stop managing the password. A saved password is still the
# one CKBunker copied, unless the user changed it in the Bunker Setup tab, so keep showing it.
if ls /mnt/hdd/mynode/ckbunker/bp-*.dat >/dev/null 2>&1; then
    if ! has_app_password ckbunker; then
        save_app_password_user_set ckbunker
    fi
elif [ -f $SETTINGS_FILE ] && ! has_app_password ckbunker; then
    CKBUNKER_PASSWORD=$(generate_app_password)
    export CKBUNKER_PASSWORD
    /usr/bin/mynode-python - <<'EOF'
import os, re
path = "/mnt/hdd/mynode/ckbunker/settings.yaml"
with open(path) as f:
    text = f.read()
text, count = re.subn(r'(?m)^MASTER_PW:.*$', lambda m: "MASTER_PW: " + os.environ["CKBUNKER_PASSWORD"], text)
if count != 1:
    raise SystemExit("MASTER_PW not found in " + path)
with open(path, "w") as f:
    f.write(text)
EOF
    chown bitcoin:bitcoin $SETTINGS_FILE
    chmod 600 $SETTINGS_FILE
    save_app_default_password ckbunker "$CKBUNKER_PASSWORD"
    unset CKBUNKER_PASSWORD
fi
