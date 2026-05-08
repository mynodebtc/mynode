#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

APP_DIR="/opt/mynode/canary"
VERSION="${VERSION:-v1.5.0}"
VERSION_FILE="/mnt/hdd/mynode/settings/canary_version"

write_compose_file() {
    cat > "$APP_DIR/docker-compose.yml" <<EOF
version: "3.8"

services:
  backend:
    image: canary-backend:latest
    network_mode: host
    restart: unless-stopped
    stop_grace_period: 30s
    volumes:
      - /mnt/hdd/mynode/canary:/app/data
    env_file:
      - /mnt/hdd/mynode/canary/canary.env
    environment:
      CANARY_DATA_DIR: /app/data
      CANARY_ELECTRUM_URL: tcp://127.0.0.1:50001
      CANARY_NETWORK: mainnet
      CANARY_MODE: self-hosted
      CANARY_BIND_ADDRESS: 127.0.0.1:3004

  frontend:
    image: canary-frontend:latest
    network_mode: host
    restart: unless-stopped
    stop_grace_period: 30s
    depends_on:
      - backend
    environment:
      API_URL: http://127.0.0.1:3004
      PORT: "3005"
EOF
}

mkdir -p /opt/mynode/canary || true
mkdir -p /mnt/hdd/mynode/canary || true

write_compose_file

cd "$APP_DIR"
/usr/local/bin/docker-compose down --remove-orphans 2>/dev/null || true

remove_docker_images_by_name "canary-backend"
remove_docker_images_by_name "canary-frontend"

docker pull schjonhaug/canary-backend:$VERSION
docker pull schjonhaug/canary-frontend:$VERSION

docker tag schjonhaug/canary-backend:$VERSION canary-backend:latest
docker tag schjonhaug/canary-frontend:$VERSION canary-frontend:latest

echo "$VERSION" > "$VERSION_FILE"
chown bitcoin:bitcoin "$VERSION_FILE"
touch /tmp/need_application_refresh

chown -R bitcoin:bitcoin /mnt/hdd/mynode/canary

echo "================== DONE INSTALLING APP ================="
