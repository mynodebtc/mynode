#!/bin/bash

set -e

APP_DIR="/opt/mynode/canary"

# Keep the compose file in sync with the packaged app data.
cp -f "$APP_DIR/app_data/docker-compose.yml" "$APP_DIR/docker-compose.yml"

# Ensure data directory exists before starting.
mkdir -p /mnt/hdd/mynode/canary
chown -R bitcoin:bitcoin /mnt/hdd/mynode/canary
