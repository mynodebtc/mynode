#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

echo "==================== UNINSTALLING APP ===================="

# The app folder will be removed automatically after this script runs. You may not need to do anything here.

rm -f /usr/local/go/bin/lntop

echo "================== DONE UNINSTALLING APP ================="
