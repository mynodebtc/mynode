#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

echo "==================== UNINSTALLING APP ===================="

# The app folder will be removed automatically after this script runs. You may not need to do anything here.

# Clear any old images, only if they exist
docker images --format '{{.Repository}}:{{.Tag}}' | grep 'albyhub' | xargs --no-run-if-empty docker rmi
docker images --format '{{.Repository}}:{{.Tag}}' | grep 'ghcr.io/getalby/hub' | xargs --no-run-if-empty docker rmi

echo "================== DONE UNINSTALLING APP ================="
