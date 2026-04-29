#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

set -x

echo "==================== UNINSTALLING APP ===================="

cp -f app_data/docker-compose.yml docker-compose.yml 2>/dev/null || true
/usr/local/bin/docker-compose down --remove-orphans 2>/dev/null || true


remove_docker_images_by_name "canary-backend"
remove_docker_images_by_name "canary-frontend"

rm -rf /mnt/hdd/mynode/canary

echo "================== DONE UNINSTALLING APP ================="
