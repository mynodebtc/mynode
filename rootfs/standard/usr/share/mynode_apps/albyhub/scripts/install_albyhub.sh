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

# Make dir that is used as .service Workdirectory if not exist
mkdir -p /opt/mynode/albyhub || true
# Make dir that will be volume mounted to the container if not exist
mkdir -p /mnt/hdd/mynode/albyhub || true
# no backup / restore implemented

# Clear any old images, only if they exist
docker images --format '{{.Repository}}:{{.Tag}}' | grep 'albyhub' | xargs --no-run-if-empty docker rmi
docker images --format '{{.Repository}}:{{.Tag}}' | grep 'ghcr.io/getalby/hub' | xargs --no-run-if-empty docker rmi

# Pull ready dockers, instead of source
docker pull ghcr.io/getalby/hub:$ALBYHUB_VERSION
docker tag ghcr.io/getalby/hub:$ALBYHUB_VERSION albyhub

echo "================== DONE INSTALLING APP ================="
