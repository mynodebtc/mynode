#!/bin/bash

set -e

# Keep the compose file in sync with the packaged app data.
cp -f app_data/docker-compose.yml docker-compose.yml

# Ensure data directory exists before starting.
mkdir -p /mnt/hdd/mynode/canary
chown -R bitcoin:bitcoin /mnt/hdd/mynode/canary
