#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

set -x

echo "==================== UNINSTALLING APP ===================="

APP_DIR="/opt/mynode/canary"
VERSION_FILE="/mnt/hdd/mynode/settings/canary_version"

remove_canary_images() {
    docker images --format '{{.Repository}}:{{.Tag}}' \
        | grep -E '^(canary-backend|canary-frontend|schjonhaug/canary-backend|schjonhaug/canary-frontend):' \
        | xargs -r docker rmi 2>/dev/null || true
}

cp -f "$APP_DIR/app_data/docker-compose.yml" "$APP_DIR/docker-compose.yml" 2>/dev/null || true
cd "$APP_DIR" 2>/dev/null || true
/usr/local/bin/docker-compose down --remove-orphans 2>/dev/null || true


remove_canary_images

rm -f "$VERSION_FILE"
rm -rf /mnt/hdd/mynode/canary
touch /tmp/need_application_refresh

echo "================== DONE UNINSTALLING APP ================="
