#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

mkdir -p /opt/mynode/canary || true
mkdir -p /mnt/hdd/mynode/canary || true

cp -f app_data/docker-compose.yml docker-compose.yml

/usr/local/bin/docker-compose down --remove-orphans 2>/dev/null || true

remove_docker_images_by_name "canary-backend"
remove_docker_images_by_name "canary-frontend"

docker pull schjonhaug/canary-backend:$VERSION
docker pull schjonhaug/canary-frontend:$VERSION

docker tag schjonhaug/canary-backend:$VERSION canary-backend:latest
docker tag schjonhaug/canary-frontend:$VERSION canary-frontend:latest

chown -R bitcoin:bitcoin /mnt/hdd/mynode/canary

echo "================== DONE INSTALLING APP ================="
