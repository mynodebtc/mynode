#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

# The current directory is the app install folder and the app tarball from GitHub
# has already been downloaded and extracted. Any additional env variables specified
# in the JSON file are also present.

# Remove old containers
docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'lndboss') || true

# Build docker container
if [ "$DEVICE_ARCH" = "x86_64" ]; then
    docker build -t lndboss .
elif [ "$DEVICE_ARCH" = "aarch64" ]; then
    docker build . -t lndboss -f arm64.Dockerfile
else
    echo "THIS ARCHITECTURE IS NOT SUPPORTED FOR LndBoss"
    exit 1
fi

echo "================== DONE INSTALLING APP ================="