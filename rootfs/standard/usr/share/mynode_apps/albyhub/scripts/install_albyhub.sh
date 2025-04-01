#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

# The current directory is the app install folder and the app tarball from GitHub
# has already been downloaded and extracted. Any additional env variables specified
# in the JSON file are also present.

#echo "DOCKER NAME: $DOCKER_IMAGE_NAME"
#echo "VERSION: $VERSION"

# TODO: Perform installation steps here

# Make dir that will be volume mounted to the container
# add check if exists
# if not exists see if _backup exists and populate from there
mkdir -p /opt/mynode/albyhub || true

# Clear any old images
docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'albyhub') || true
docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'ghcr.io/getalby/hub') || true

# Use ready dockers, instead of source

# Pull docker image
docker pull ghcr.io/getalby/hub:$ALBYHUB_VERSION
docker tag ghcr.io/getalby/hub:$ALBYHUB_VERSION albyhub

# somehow password should be set automatically and backed up too with data, cause it cant be changed!

#If exists both
cp -av /mnt/hdd/mynode/albyhub_backup/* /mnt/hdd/mynode/albyhub/

# Build docker image (slow)
# docker build -t albyhub .

echo "================== DONE INSTALLING APP ================="
