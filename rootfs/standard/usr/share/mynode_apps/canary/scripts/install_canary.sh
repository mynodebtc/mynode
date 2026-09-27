#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

pull_image_with_retries() {
    local image="$1"
    local attempt

    for attempt in 1 2 3 4 5; do
        if pull_app_docker_image "$@"; then
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

BACKEND_IMAGE_DIGEST="v1.7.0 sha256:d5025d4be7af7c0b2a53086fd587375d54d4455da1de2cdfed7bdc47b5e1cc27"
FRONTEND_IMAGE_DIGEST="v1.7.0 sha256:f4c5d5f8d3409ff3bc270356dfd3446e16cdd87a6ae48cddfac658631a76227b"
pull_image_with_retries schjonhaug/canary-backend "$VERSION" canary "$BACKEND_IMAGE_DIGEST"
pull_image_with_retries schjonhaug/canary-frontend "$VERSION" canary "$FRONTEND_IMAGE_DIGEST"

docker tag schjonhaug/canary-backend:$VERSION canary-backend:latest
docker tag schjonhaug/canary-frontend:$VERSION canary-frontend:latest

chown bitcoin:bitcoin /mnt/hdd/mynode/canary

echo "================== DONE INSTALLING APP ================="
