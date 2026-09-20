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

# TODO: Perform installation steps here

# Docker apps: pull the image by a pinned "<tag> <digest>" value instead of downloading source.
# Get the pin by adding the image to MARKETPLACE_DOCKER_IMAGES in the MyNode repo's
# scripts/print_app_download_hashes.sh and running it.
#remove_docker_images_by_name '<image>'
#IMAGE_DIGEST="v0.0.1 sha256:<digest>"
#pull_app_docker_image <image> "$VERSION" sampleapp "$IMAGE_DIGEST"
#docker tag <image>:$VERSION sampleapp

echo "================== DONE INSTALLING APP ================="
