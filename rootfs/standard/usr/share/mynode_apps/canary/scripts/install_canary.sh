#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

mkdir -p /opt/mynode/canary || true
mkdir -p /mnt/hdd/mynode/canary || true

docker images --format '{{.Repository}}:{{.Tag}}' | grep 'canary-backend' | xargs --no-run-if-empty docker rmi
docker images --format '{{.Repository}}:{{.Tag}}' | grep 'schjonhaug/canary-backend' | xargs --no-run-if-empty docker rmi
docker images --format '{{.Repository}}:{{.Tag}}' | grep 'canary-frontend' | xargs --no-run-if-empty docker rmi
docker images --format '{{.Repository}}:{{.Tag}}' | grep 'schjonhaug/canary-frontend' | xargs --no-run-if-empty docker rmi

docker pull schjonhaug/canary-backend:$VERSION
docker pull schjonhaug/canary-frontend:$VERSION

docker tag schjonhaug/canary-backend:$VERSION canary-backend:latest
docker tag schjonhaug/canary-frontend:$VERSION canary-frontend:latest

chown -R bitcoin:bitcoin /mnt/hdd/mynode/canary

echo "================== DONE INSTALLING APP ================="
