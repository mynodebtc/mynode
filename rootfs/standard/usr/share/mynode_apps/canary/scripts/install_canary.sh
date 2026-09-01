#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

pull_image() {
    local image="$1"
    local attempt

    for attempt in 1 2 3 4 5; do
        if docker pull "$image"; then
            return 0
        fi

        if [ "$attempt" -lt 5 ]; then
            echo "Docker pull failed for $image (attempt $attempt/5); retrying..."
            sleep $((attempt * 5))
        fi
    done

    echo "ERROR: Docker pull failed for $image after 5 attempts" >&2
    return 1
}

write_compose_identity() {
    local compose_env=".env"
    local temp_file

    if [ -L "$compose_env" ] || { [ -e "$compose_env" ] && [ ! -f "$compose_env" ]; }; then
        echo "Refusing to replace non-regular Canary Compose environment file: $compose_env" >&2
        return 1
    fi

    temp_file=$(mktemp .canary-compose-env.XXXXXX)
    if ! printf 'CANARY_HOST_UID=%s\nCANARY_HOST_GID=%s\n' \
        "$(id -u bitcoin)" "$(id -g bitcoin)" > "$temp_file" ||
       ! chmod 600 "$temp_file" ||
       ! mv -f "$temp_file" "$compose_env"; then
        rm -f "$temp_file"
        return 1
    fi
}

mkdir -p /opt/mynode/canary || true
mkdir -p /mnt/hdd/mynode/canary || true
chmod 700 /mnt/hdd/mynode/canary

cp -f app_data/docker-compose.yml docker-compose.yml
write_compose_identity

/usr/local/bin/docker-compose down --remove-orphans 2>/dev/null || true

remove_docker_images_by_name "canary-backend"
remove_docker_images_by_name "canary-frontend"

pull_image "schjonhaug/canary-backend:$VERSION"
pull_image "schjonhaug/canary-frontend:$VERSION"

docker tag schjonhaug/canary-backend:$VERSION canary-backend:latest
docker tag schjonhaug/canary-frontend:$VERSION canary-frontend:latest

chown bitcoin:bitcoin /mnt/hdd/mynode/canary

echo "================== DONE INSTALLING APP ================="
