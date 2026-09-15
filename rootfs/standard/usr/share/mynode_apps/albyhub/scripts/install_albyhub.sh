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

#echo "DOCKER NAME: $DOCKER_IMAGE_NAME"
#echo "VERSION: $VERSION"

# Make dir that is used as .service Workdirectory if not exist
mkdir -p /opt/mynode/albyhub || true
# Make dir that will be volume mounted to the container if not exist
mkdir -p /mnt/hdd/mynode/albyhub || true
# no backup / restore implemented

# Clear any old images, only if they exist
remove_docker_images_by_name 'albyhub'
remove_docker_images_by_name 'ghcr.io/getalby/hub'

# Pull ready dockers, instead of source
IMAGE_DIGEST="v1.24.0 sha256:0227bdc79afd20eb689c922c96cf0546576b608c5cbb07b13658956d54e8133d"
pull_app_docker_image ghcr.io/getalby/hub "$VERSION" albyhub "$IMAGE_DIGEST"
docker tag ghcr.io/getalby/hub:$VERSION albyhub

echo "================== DONE INSTALLING APP ================="
