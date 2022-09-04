#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

# The current directory is the app install folder and the app tarball from GitHub
# has already been downloaded and extracted. Any additional env variables specified
# in the JSON file are also present.

# Load repos (it's OK if this is run multiple times)
# This file comes from https://tailscale.com/install.sh on 9/3/22
bash /usr/share/mynode_apps/tailscale/app_data/install_tailscale.sh


echo "================== DONE INSTALLING APP ================="