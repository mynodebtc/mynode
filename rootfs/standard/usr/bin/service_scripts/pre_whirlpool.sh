#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

# Migrate files to HDD
# Older version used SD card, but data would get lost during SD re-flash
if [[ -f /opt/mynode/whirlpool/whirlpool-cli-config.properties && ! -f /mnt/hdd/mynode/whirlpool/whirlpool-cli-config.properties ]]; then
    # Copy old files to new location
    cp -f /opt/mynode/whirlpool/whirlpool-cli-config.properties /mnt/hdd/mynode/whirlpool/whirlpool-cli-config.properties
    cp -f /opt/mynode/whirlpool/*.json /mnt/hdd/mynode/whirlpool/

    # Sync FS
    sync
fi
