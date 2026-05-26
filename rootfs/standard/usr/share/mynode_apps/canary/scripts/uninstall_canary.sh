#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

set -x

echo "==================== UNINSTALLING APP ===================="

remove_canary_images_by_name() {
    local name="$1"
    local images

    images="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep "$name" || true)"
    [ -z "$images" ] && return 0

    printf '%s\n' "$images" | xargs --no-run-if-empty docker rmi
}

cp -f app_data/docker-compose.yml docker-compose.yml 2>/dev/null || true
/usr/local/bin/docker-compose down --remove-orphans 2>/dev/null || true

remove_canary_images_by_name "canary-backend"
remove_canary_images_by_name "canary-frontend"
remove_canary_images_by_name "schjonhaug/canary-backend"
remove_canary_images_by_name "schjonhaug/canary-frontend"

rm -rf /mnt/hdd/mynode/canary

echo "================== DONE UNINSTALLING APP ================="
