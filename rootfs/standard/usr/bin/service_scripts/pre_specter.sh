#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

if [ ! -f /mnt/hdd/mynode/specter/config.json ]; then
    cp -f /usr/share/mynode/specter.conf /mnt/hdd/mynode/specter/config.json
fi
