#!/bin/bash

# Print the sha256 of app downloads that have no upstream signature or checksum, and the
# digests of the Docker images MyNode pulls. Run from the repository root after changing one
# of these app versions, and paste each line over the matching pin:
#   - built-in apps: <APP>_SHA256 / <APP>_DIGEST in rootfs/standard/usr/share/mynode/mynode_app_versions.sh
#   - marketplace apps: "download_source_sha256" in rootfs/standard/usr/share/mynode_apps/<app>/<app>.json,
#     image digests in rootfs/standard/usr/share/mynode_apps/<app>/scripts/install_<app>.sh
# Pass app names (e.g. THUNDERHUB lndg) to check only those. Image digests need docker buildx.

set -e

VERSIONS_FILE=rootfs/standard/usr/share/mynode/mynode_app_versions.sh
UPGRADE_FILE=rootfs/standard/usr/bin/mynode_post_upgrade.sh
DOCKER_IMAGES_FILE=rootfs/standard/usr/bin/mynode_docker_images.sh
MARKETPLACE_DIR=rootfs/standard/usr/share/mynode_apps

# Variable prefixes, matching <APP>_VERSION in VERSIONS_FILE and <APP>_UPGRADE_URL in UPGRADE_FILE, DOCKER_IMAGES_FILE or VERSIONS_FILE
APPS="LNDHUB THUNDERHUB CARAVAN CORSPROXY JOININBOX BTCRPCEXPLORER CKBUNKER SPHINXRELAY PYBLOCK WARDENTERMINAL LOG2RAM WEBSSH2"

# Marketplace app short names, using latest_version and download_source_url from their JSON
MARKETPLACE_APPS="astral datum lilywallet lndboss lndg nostrrsrelay publicpool publicpoolui wetty"

# Docker images pulled by mynode_docker_images.sh: <pin variable> <image> <version variable, or a fixed tag>
DOCKER_IMAGES="
NETDATA_DIGEST netdata/netdata NETDATA_VERSION
MEMPOOL_FRONTEND_DIGEST mempool/frontend MEMPOOL_VERSION
MEMPOOL_BACKEND_DIGEST mempool/backend MEMPOOL_VERSION
MARIADB_DIGEST mariadb 10.9.3
LNBITS_DIGEST lnbits/lnbits LNBITS_VERSION
"

# Docker images pulled by marketplace install scripts: <app> <pin variable> <image> <tag, with {VERSION} from its JSON>
MARKETPLACE_DOCKER_IMAGES="
albyhub IMAGE_DIGEST ghcr.io/getalby/hub {VERSION}
canary BACKEND_IMAGE_DIGEST schjonhaug/canary-backend {VERSION}
canary FRONTEND_IMAGE_DIGEST schjonhaug/canary-frontend {VERSION}
jam IMAGE_DIGEST ghcr.io/joinmarket-webui/jam-ui-only {VERSION}-clientserver-v0.9.11
lndboss IMAGE_DIGEST niteshbalusu/lndboss {VERSION}
"

SELECTED=("$@")

wanted () {
    [ ${#SELECTED[@]} -eq 0 ] && return 0
    for s in "${SELECTED[@]}"; do
        [ "$s" = "$1" ] && return 0
    done
    return 1
}

sha256_of () {
    if command -v sha256sum > /dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# Digest of the image index (all platforms), which is what the device pulls by
digest_of () {
    docker buildx imagetools inspect "$1" < /dev/null | awk '$1 == "Digest:" {print $2; exit}'
}

status_of () {
    if [ -z "$1" ]; then
        echo "new"
    elif [ "$1" = "$2" ]; then
        echo "matches"
    else
        echo "differs from current: $1"
    fi
}

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

for APP in $APPS; do
    wanted "$APP" || continue
    URL_TEMPLATE=$(grep -h -m1 "${APP}_UPGRADE_URL=" $UPGRADE_FILE $DOCKER_IMAGES_FILE $VERSIONS_FILE | head -1 | sed 's/^ *//' | cut -d= -f2-)
    # Every literal version, including overrides for older systems
    VERSIONS=$(grep -E "^[[:space:]]*${APP}_VERSION=\"[^\$\"]+\"" $VERSIONS_FILE | cut -d'"' -f2)
    if [ -z "$VERSIONS" ] || [ -z "$URL_TEMPLATE" ]; then
        echo "ERROR: could not determine version or URL for $APP" >&2
        exit 1
    fi

    for VERSION in $VERSIONS; do
        URL=${URL_TEMPLATE//\$\{${APP}_VERSION\}/$VERSION}
        URL=${URL//\$${APP}_VERSION/$VERSION}
        if [[ "$URL" == *'$'* ]]; then
            echo "ERROR: could not determine URL for $APP $VERSION" >&2
            exit 1
        fi
        curl -fsSL "$URL" -o "$TMP_DIR/download"
        PINNED="$VERSION $(sha256_of "$TMP_DIR/download")"
        CURRENT=$(grep -E "^[[:space:]]*${APP}_SHA256=\"" $VERSIONS_FILE | grep -F "\"$VERSION " | head -1 | cut -d'"' -f2)
        echo "${APP}_SHA256=\"$PINNED\"    # $(status_of "$CURRENT" "$PINNED")"
    done
done

for APP in $MARKETPLACE_APPS; do
    wanted "$APP" || continue
    JSON="$MARKETPLACE_DIR/$APP/$APP.json"
    # The device uses at most 16 characters of the version (commit IDs are shortened)
    IFS=$'\t' read -r VERSION URL CURRENT < <(python3 - "$JSON" <<'EOF'
import json, sys
app = json.load(open(sys.argv[1]))
version = app["latest_version"][0:16]
url = app["download_source_url"].replace("{VERSION}", version).replace("{SHORT_NAME}", app["short_name"])
print("\t".join([version, url, app.get("download_source_sha256", "")]))
EOF
)
    if [ -z "$VERSION" ] || [ -z "$URL" ] || [[ "$URL" == *'{'* ]]; then
        echo "ERROR: could not determine version or URL for $APP" >&2
        exit 1
    fi

    curl -fsSL "$URL" -o "$TMP_DIR/download"
    PINNED="$VERSION $(sha256_of "$TMP_DIR/download")"
    echo "$APP: \"download_source_sha256\": \"$PINNED\",    # $(status_of "$CURRENT" "$PINNED")"
done

while read -r VAR IMAGE TAG_SOURCE; do
    [ -n "$VAR" ] || continue
    wanted "${VAR%%_*}" || continue
    if [[ "$TAG_SOURCE" == *_VERSION ]]; then
        TAGS=$(grep -E "^[[:space:]]*${TAG_SOURCE}=\"[^\$\"]+\"" $VERSIONS_FILE | cut -d'"' -f2)
    else
        TAGS=$TAG_SOURCE
    fi
    for TAG in $TAGS; do
        DIGEST=$(digest_of "$IMAGE:$TAG")
        if [ -z "$DIGEST" ]; then
            echo "ERROR: could not get the digest of $IMAGE:$TAG" >&2
            exit 1
        fi
        PINNED="$TAG $DIGEST"
        CURRENT=$(grep -E "^[[:space:]]*${VAR}=\"" $VERSIONS_FILE | grep -F "\"$TAG " | head -1 | cut -d'"' -f2)
        echo "${VAR}=\"$PINNED\"    # $(status_of "$CURRENT" "$PINNED")"
    done
done <<< "$DOCKER_IMAGES"

while read -r APP VAR IMAGE TAG_TEMPLATE; do
    [ -n "$APP" ] || continue
    wanted "$APP" || continue
    VERSION=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["latest_version"])' "$MARKETPLACE_DIR/$APP/$APP.json" < /dev/null)
    TAG=${TAG_TEMPLATE//\{VERSION\}/$VERSION}
    DIGEST=$(digest_of "$IMAGE:$TAG")
    if [ -z "$DIGEST" ]; then
        echo "ERROR: could not get the digest of $IMAGE:$TAG" >&2
        exit 1
    fi
    PINNED="$TAG $DIGEST"
    CURRENT=$(grep -E "^[[:space:]]*${VAR}=\"" "$MARKETPLACE_DIR/$APP/scripts/install_$APP.sh" | head -1 | cut -d'"' -f2)
    echo "$APP: ${VAR}=\"$PINNED\"    # $(status_of "$CURRENT" "$PINNED")"
done <<< "$MARKETPLACE_DOCKER_IMAGES"

# btcpayserver-docker has no releases; its setup script runs from a pinned commit
if wanted BTCPAYSERVER; then
    LATEST=$(git ls-remote https://github.com/btcpayserver/btcpayserver-docker HEAD < /dev/null | cut -f1)
    CURRENT=$(grep -E '^BTCPAYSERVER_DOCKER_COMMIT="' $VERSIONS_FILE | cut -d'"' -f2)
    echo "BTCPAYSERVER_DOCKER_COMMIT=\"$LATEST\"    # latest commit, $(status_of "$CURRENT" "$LATEST")"
fi
