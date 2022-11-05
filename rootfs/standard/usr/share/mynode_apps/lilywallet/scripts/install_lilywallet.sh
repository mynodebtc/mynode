#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

# Copy over custom compose file for mynode
cp -f app_data/docker-compose.yml docker-compose.yml

sed -i "s/RUN yarn/RUN yarn --network-timeout 120000/g" Dockerfile

# Build images
docker-compose build --no-cache

echo "================== DONE INSTALLING APP ================="