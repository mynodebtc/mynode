#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

# The current directory is the app install folder and the app tarball from GitHub
# has already been downloaded and extracted. Any additional env variables specified
# in the JSON file are also present.

# Setup folders and config
mkdir -p /mnt/hdd/mynode/nostrrsrelay/data
if [ ! -f /mnt/hdd/mynode/nostrrsrelay/app_data/config.toml ]; then
    cp -f /usr/share/mynode_apps/nostrrsrelay/app_data/config.toml /mnt/hdd/mynode/nostrrsrelay/config.toml
fi

# Remove old containers
docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'nostrrsrelay') || true

# Build docker container
docker build -t nostrrsrelay .

echo "================== DONE INSTALLING APP ================="