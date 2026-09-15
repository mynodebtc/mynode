#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

# The current directory is the app install folder and the app tarball from GitHub
# has already been downloaded and extracted. Any additional env variables specified
# in the JSON file are also present.

# Install the locked dependencies with yarn (via corepack) and build with the project's own
# quasar CLI. nginx serves the build from dist/pwa.
export COREPACK_HOME="$(pwd)/.corepack"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
corepack yarn install --frozen-lockfile
npx --no quasar build -m pwa

echo "================== DONE INSTALLING APP ================="