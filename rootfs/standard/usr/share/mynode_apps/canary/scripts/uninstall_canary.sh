#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

echo "==================== UNINSTALLING APP ===================="

docker stop canary canary-frontend 2>/dev/null || true
docker rm canary canary-frontend 2>/dev/null || true

docker images --format '{{.Repository}}:{{.Tag}}' | grep 'canary-backend' | xargs --no-run-if-empty docker rmi
docker images --format '{{.Repository}}:{{.Tag}}' | grep 'schjonhaug/canary-backend' | xargs --no-run-if-empty docker rmi
docker images --format '{{.Repository}}:{{.Tag}}' | grep 'canary-frontend' | xargs --no-run-if-empty docker rmi
docker images --format '{{.Repository}}:{{.Tag}}' | grep 'schjonhaug/canary-frontend' | xargs --no-run-if-empty docker rmi

rm -rf /mnt/hdd/mynode/canary

echo "================== DONE UNINSTALLING APP ================="
