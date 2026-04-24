#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

echo "==================== UNINSTALLING APP ===================="

# The app folder will be removed automatically after this script runs. You may not need to do anything here.

# Clear any old images, only if they exist
remove_docker_images_by_name 'albyhub'
remove_docker_images_by_name 'ghcr.io/getalby/hub'

# no backup / restore implemented

echo "================== DONE UNINSTALLING APP ================="
