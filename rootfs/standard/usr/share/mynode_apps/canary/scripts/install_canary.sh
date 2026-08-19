#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

mkdir -p /opt/mynode/canary || true
mkdir -p /mnt/hdd/mynode/canary || true
chmod 700 /mnt/hdd/mynode/canary

cp -f app_data/docker-compose.yml docker-compose.yml

/usr/local/bin/docker-compose down --remove-orphans 2>/dev/null || true

remove_docker_images_by_name "canary-backend"
remove_docker_images_by_name "canary-frontend"

BACKEND_IMAGE_DIGEST="v1.5.2 sha256:a927448e881d6e1060736a844439dd57b84e4e3f8b89aeaf3dea48367c40fa55"
FRONTEND_IMAGE_DIGEST="v1.5.2 sha256:72ecf65fcdc80613974c2ea603524b2edc053026fc9f93ba3198be9f89711a6c"
pull_app_docker_image schjonhaug/canary-backend "$VERSION" canary "$BACKEND_IMAGE_DIGEST"
pull_app_docker_image schjonhaug/canary-frontend "$VERSION" canary "$FRONTEND_IMAGE_DIGEST"

docker tag schjonhaug/canary-backend:$VERSION canary-backend:latest
docker tag schjonhaug/canary-frontend:$VERSION canary-frontend:latest

chown bitcoin:bitcoin /mnt/hdd/mynode/canary

echo "================== DONE INSTALLING APP ================="
