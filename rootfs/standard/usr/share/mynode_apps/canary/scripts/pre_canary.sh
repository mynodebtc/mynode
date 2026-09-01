#!/bin/bash

set -eu

# Secrets must be private from the moment their files are created.
umask 077

source /usr/share/mynode/mynode_functions.sh

DATA_DIR="/mnt/hdd/mynode/canary"
INSTALL_DIR="/opt/mynode/canary"
ADMIN_PASSWORD_FILE="$DATA_DIR/admin_password"
JWT_SECRET_FILE="$DATA_DIR/jwt_secret"
ENV_FILE="$DATA_DIR/canary.env"
COMPOSE_ENV_FILE="$INSTALL_DIR/.env"

generate_secret() {
    local byte_count="$1"
    od -An -N "$byte_count" -tx1 /dev/urandom | tr -d '[:space:]'
}

ensure_secret() {
    local secret_file="$1"
    local byte_count="$2"
    local expected_length=$((byte_count * 2))
    local temp_file

    # Never follow a path controlled from inside the bind-mounted data directory.
    if [ -L "$secret_file" ]; then
        echo "Refusing to use symlinked Canary secret: $secret_file" >&2
        return 1
    fi

    if [ -s "$secret_file" ]; then
        if [ ! -f "$secret_file" ]; then
            echo "Canary secret is not a regular file: $secret_file" >&2
            return 1
        fi
        return 0
    fi

    if [ -e "$secret_file" ] && [ ! -f "$secret_file" ]; then
        echo "Cannot replace non-regular Canary secret: $secret_file" >&2
        return 1
    fi

    if ! temp_file=$(mktemp "$DATA_DIR/.canary-secret.XXXXXX"); then
        echo "Failed to create a temporary Canary secret file" >&2
        return 1
    fi
    if ! generate_secret "$byte_count" > "$temp_file" ||
       [ "$(wc -c < "$temp_file")" -ne "$expected_length" ] ||
       ! chmod 600 "$temp_file" ||
       ! chown bitcoin:bitcoin "$temp_file" ||
       ! mv -f "$temp_file" "$secret_file"; then
        rm -f "$temp_file"
        echo "Failed to generate Canary secret: $secret_file" >&2
        return 1
    fi
}

write_env_file() {
    local admin_password
    local jwt_secret
    local temp_file

    if ! admin_password=$(cat "$ADMIN_PASSWORD_FILE") ||
       ! jwt_secret=$(cat "$JWT_SECRET_FILE"); then
        echo "Failed to read Canary secrets" >&2
        return 1
    fi

    if ! temp_file=$(mktemp "$DATA_DIR/.canary.env.XXXXXX"); then
        echo "Failed to create a temporary Canary environment file" >&2
        return 1
    fi

    if ! printf 'CANARY_SELF_HOSTED_ADMIN_PASSWORD=%s\nJWT_SECRET=%s\n' \
        "$admin_password" "$jwt_secret" > "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi

    if is_service_enabled mempool; then
        if ! printf '%s\n' 'CANARY_MEMPOOL_PORT=4080' >> "$temp_file"; then
            rm -f "$temp_file"
            return 1
        fi
    fi

    if is_service_enabled btcrpcexplorer; then
        if ! printf '%s\n' 'CANARY_BTC_RPC_EXPLORER_PORT=3002' >> "$temp_file"; then
            rm -f "$temp_file"
            return 1
        fi
    fi

    if is_service_enabled mempool || is_service_enabled btcrpcexplorer; then
        if ! printf '%s\n' 'CANARY_TX_EXPLORER_PLATFORM=mynode' >> "$temp_file"; then
            rm -f "$temp_file"
            return 1
        fi
    fi

    if ! chmod 600 "$temp_file" ||
       ! chown bitcoin:bitcoin "$temp_file" ||
       ! mv -f "$temp_file" "$ENV_FILE"; then
        rm -f "$temp_file"
        return 1
    fi
}

write_compose_env_file() {
    local temp_file

    if [ -L "$COMPOSE_ENV_FILE" ] || { [ -e "$COMPOSE_ENV_FILE" ] && [ ! -f "$COMPOSE_ENV_FILE" ]; }; then
        echo "Refusing to replace non-regular Canary Compose environment file: $COMPOSE_ENV_FILE" >&2
        return 1
    fi

    if ! temp_file=$(mktemp "$INSTALL_DIR/.canary-compose-env.XXXXXX"); then
        echo "Failed to create a temporary Canary Compose environment file" >&2
        return 1
    fi

    if ! printf 'CANARY_HOST_UID=%s\nCANARY_HOST_GID=%s\n' \
        "$(id -u bitcoin)" "$(id -g bitcoin)" > "$temp_file" ||
       ! chmod 600 "$temp_file" ||
       ! chown bitcoin:bitcoin "$temp_file" ||
       ! mv -f "$temp_file" "$COMPOSE_ENV_FILE"; then
        rm -f "$temp_file"
        return 1
    fi
}

cp -f app_data/docker-compose.yml docker-compose.yml

# Ensure data directory exists before starting.
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR"

if ! write_compose_env_file; then
    echo "Failed to write Canary Compose environment file" >&2
    exit 1
fi

ensure_secret "$ADMIN_PASSWORD_FILE" 24
ensure_secret "$JWT_SECRET_FILE" 32

if [ -L "$ENV_FILE" ] || { [ -e "$ENV_FILE" ] && [ ! -f "$ENV_FILE" ]; }; then
    echo "Refusing to replace non-regular Canary environment file: $ENV_FILE" >&2
    exit 1
fi

if ! write_env_file; then
    echo "Failed to write Canary environment file" >&2
    exit 1
fi

chown bitcoin:bitcoin "$DATA_DIR" "$ADMIN_PASSWORD_FILE" "$JWT_SECRET_FILE" "$ENV_FILE"
chmod 600 "$ADMIN_PASSWORD_FILE" "$JWT_SECRET_FILE" "$ENV_FILE"
