#!/bin/bash

source /usr/share/mynode/mynode_functions.sh

set -e

# Set the master login password the first time CKBunker starts with MyNode's settings file.
# A password saved in the CKBunker Bunker Setup tab takes precedence over this one.
SETTINGS_FILE=/mnt/hdd/mynode/ckbunker/settings.yaml
if [ -f $SETTINGS_FILE ] && ! has_app_password ckbunker; then
    CKBUNKER_PASSWORD=$(generate_app_password)
    export CKBUNKER_PASSWORD
    /usr/local/bin/python3 - <<'EOF'
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
    save_app_password ckbunker "$CKBUNKER_PASSWORD"
    unset CKBUNKER_PASSWORD
fi
