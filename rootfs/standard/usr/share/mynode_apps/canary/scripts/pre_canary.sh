#!/bin/bash

set -e

DATA_DIR="/mnt/hdd/mynode/canary"
ADMIN_PASSWORD_FILE="$DATA_DIR/admin_password"
JWT_SECRET_FILE="$DATA_DIR/jwt_secret"
ENV_FILE="$DATA_DIR/canary.env"

generate_secret() {
    local length="$1"
    tr -dc A-Za-z0-9 < /dev/urandom | head -c "$length"
}

cp -f app_data/docker-compose.yml docker-compose.yml

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

chown -R bitcoin:bitcoin "$DATA_DIR"
chmod 600 "$ADMIN_PASSWORD_FILE" "$JWT_SECRET_FILE" "$ENV_FILE"
