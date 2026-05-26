#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

VERSION="${VERSION:-v1.5.1}"

remove_canary_images_by_name() {
    local name="$1"
    local images

    images="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep "$name" || true)"
    [ -z "$images" ] && return 0

    printf '%s\n' "$images" | xargs --no-run-if-empty docker rmi
}

mkdir -p /opt/mynode/canary || true
mkdir -p /mnt/hdd/mynode/canary || true

cp -f app_data/docker-compose.yml docker-compose.yml

/usr/local/bin/docker-compose down --remove-orphans 2>/dev/null || true

remove_canary_images_by_name "canary-backend"
remove_canary_images_by_name "canary-frontend"

docker pull schjonhaug/canary-backend:$VERSION
docker pull schjonhaug/canary-frontend:$VERSION

docker tag schjonhaug/canary-backend:$VERSION canary-backend:latest
docker tag schjonhaug/canary-frontend:$VERSION canary-frontend:latest

chown -R bitcoin:bitcoin /mnt/hdd/mynode/canary

echo "================== DONE INSTALLING APP ================="
