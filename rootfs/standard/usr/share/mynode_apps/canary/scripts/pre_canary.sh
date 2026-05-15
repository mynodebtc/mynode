#!/bin/bash

set -e

APP_DIR="/opt/mynode/canary"
DATA_DIR="/mnt/hdd/mynode/canary"
VERSION_FILE="/mnt/hdd/mynode/settings/canary_version"
VERSION="${VERSION:-$(cat "$VERSION_FILE" 2>/dev/null || echo v1.5.0)}"
ADMIN_PASSWORD_FILE="$DATA_DIR/admin_password"
JWT_SECRET_FILE="$DATA_DIR/jwt_secret"
ENV_FILE="$DATA_DIR/canary.env"

write_compose_file() {
    mkdir -p "$APP_DIR"
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

generate_secret() {
    local length="$1"
    tr -dc A-Za-z0-9 < /dev/urandom | head -c "$length"
}

service_is_enabled() {
    local service_name="$1"
    systemctl is-enabled "$service_name" > /dev/null 2>&1
}

write_compose_file

# Ensure data directory exists before starting.
mkdir -p "$DATA_DIR"

if [ ! -s "$ADMIN_PASSWORD_FILE" ]; then
    generate_secret 32 > "$ADMIN_PASSWORD_FILE"
fi

if [ ! -s "$JWT_SECRET_FILE" ]; then
    generate_secret 64 > "$JWT_SECRET_FILE"
fi

cat > "$ENV_FILE" <<EOF
CANARY_SELF_HOSTED_ADMIN_PASSWORD=$(cat "$ADMIN_PASSWORD_FILE")
JWT_SECRET=$(cat "$JWT_SECRET_FILE")
EOF

if service_is_enabled mempool; then
    echo "CANARY_MEMPOOL_PORT=4080" >> "$ENV_FILE"
fi

if service_is_enabled btcrpcexplorer; then
    echo "CANARY_BTC_RPC_EXPLORER_PORT=3002" >> "$ENV_FILE"
fi

if service_is_enabled mempool || service_is_enabled btcrpcexplorer; then
    echo "CANARY_TX_EXPLORER_PLATFORM=mynode" >> "$ENV_FILE"
fi

chown -R bitcoin:bitcoin "$DATA_DIR"
chmod 600 "$ADMIN_PASSWORD_FILE" "$JWT_SECRET_FILE" "$ENV_FILE"
