#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

echo "==================== UNINSTALLING APP ===================="

# The app folder will be removed automatically after this script runs. You may not need to do anything here.

# Remove old containers
remove_docker_images_by_name 'lndboss'
remove_docker_images_by_name 'lndboss:latest'

echo "================== DONE UNINSTALLING APP ================="
