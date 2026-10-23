#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

# The current directory is the app install folder and the app tarball from GitHub
# has already been downloaded and extracted. Any additional env variables specified
# in the JSON file are also present.

# Remove old containers
remove_docker_images_by_name 'lndboss'
remove_docker_images_by_name 'lndboss:latest'

# Pull latest image and tag latest
# IMAGE_DIGEST is set from install_env_vars in lndboss.json
pull_app_docker_image niteshbalusu/lndboss "$VERSION" lndboss "$IMAGE_DIGEST"
docker tag niteshbalusu/lndboss:$VERSION lndboss

# Build docker container
#if [ "$DEVICE_ARCH" = "x86_64" ]; then
#    docker build -t lndboss .
#elif [ "$DEVICE_ARCH" = "aarch64" ]; then
#    docker build . -t lndboss -f arm64.Dockerfile
#else
#    echo "THIS ARCHITECTURE IS NOT SUPPORTED FOR LndBoss"
#    exit 1
#fi

echo "================== DONE INSTALLING APP ================="