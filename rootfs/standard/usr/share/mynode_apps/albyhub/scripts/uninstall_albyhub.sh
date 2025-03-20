#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

echo "==================== UNINSTALLING APP ===================="

# The app folder will be removed automatically after this script runs. You may not need to do anything here.

# TODO: Perform special uninstallation steps here

# if pulled docker used
docker rmi $(sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep 'albyhub') || true
docker rmi $(sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep 'ghcr.io/getalby/hub') || true

# if source build docked used
#docker rmi $(sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep 'albyhub') || true

echo "================== DONE UNINSTALLING APP ================="
