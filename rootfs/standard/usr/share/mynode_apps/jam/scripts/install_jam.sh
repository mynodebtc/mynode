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

# Make dir that will be volume mounted to the container
mkdir -p ${STORAGE_FOLDER}/data

# Clear any old images
docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep 'jam-') || true
docker rmi jam:latest || true

# Pull latest image
docker pull ghcr.io/joinmarket-webui/$DOCKER_IMAGE_NAME

# Tag latest as "jam:latest"
docker tag ghcr.io/joinmarket-webui/$DOCKER_IMAGE_NAME jam-orig:latest

rm -rf /tmp/jam
mkdir -p /tmp/jam
cat << EOF > /tmp/jam/Dockerfile
FROM jam-orig:latest

RUN sed -i 's/zone upstreams 64K/zone upstreams 256K/g' /etc/nginx/conf.d/default.conf
EOF
docker build -t jam:latest /tmp/jam

echo "================== DONE INSTALLING APP ================="