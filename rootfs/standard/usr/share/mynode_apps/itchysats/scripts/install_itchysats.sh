#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

# The current directory is the app install folder and the app tarball from GitHub
# has already been downloaded and extracted. Any additional env variables specified
# in the JSON file are also present.

mynode-install-extra rust

yarn --cwd=./taker-frontend install
yarn --cwd=./taker-frontend build

/home/bitcoin/.cargo/bin/cargo build --release --bin taker
sudo install -g root -o root target/release/taker /usr/bin/itchysats

echo "================== DONE INSTALLING APP ================="
