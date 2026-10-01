#!/bin/bash

# This will run prior to launching the application

# Update docker compose with custom one
cp -f app_data/docker-compose.yml docker-compose.yml

# The local Lightning wallet is no longer added for you. Take it out of a config that has
# not been set up yet (one that has been set up is not readable here and is left alone).
CONFIG_FILE=/mnt/hdd/mynode/lilywallet/lily-config-encrypted.txt
if [ -f $CONFIG_FILE ]; then
    CONFIG_FILE=$CONFIG_FILE /usr/local/bin/python3 - <<'EOF' || true
import json, os
path = os.environ["CONFIG_FILE"]
try:
    with open(path) as f:
        config = json.load(f)
except ValueError:
    config = None
if isinstance(config, dict) and config.get("lightning"):
    config["lightning"] = []
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(config, f)
    os.replace(tmp, path)
EOF
fi
