#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

# The current directory is the app install folder and the app tarball from GitHub
# has already been downloaded and extracted. Any additional env variables specified
# in the JSON file are also present.

# Build with the pnpm version pinned by the project (via corepack). The wetty user has no
# home folder, so corepack and the pnpm store are kept in the install folder.
export COREPACK_HOME="$(pwd)/.corepack"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
mkdir -p .corepack/bin
corepack enable --install-directory "$(pwd)/.corepack/bin" pnpm
export PATH="$(pwd)/.corepack/bin:$PATH"

pnpm install --frozen-lockfile --store-dir "$(pwd)/.pnpm-store"
pnpm build

echo "================== DONE INSTALLING APP ================="