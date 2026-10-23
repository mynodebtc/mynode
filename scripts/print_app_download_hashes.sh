#!/bin/bash

# Print the sha256 of app downloads that have no upstream signature or checksum, and the
# digests of the Docker images MyNode pulls. Run from the repository root after changing one
# of these app versions, and paste each line over the matching pin:
#   - built-in apps: <APP>_SHA256 / <APP>_DIGEST in rootfs/standard/usr/share/mynode/mynode_app_versions.sh
#   - marketplace apps: "download_source_sha256" in rootfs/standard/usr/share/mynode_apps/<app>/<app>.json,
#     image digests in rootfs/standard/usr/share/mynode_apps/<app>/scripts/install_<app>.sh, or in
#     "install_env_vars" in the app's JSON
# Pass app names (e.g. THUNDERHUB lndg GO) to check only those. Image digests need docker buildx.
# With --check, exit with an error if any pin is missing or does not match (for CI).

set -e

VERSIONS_FILE=rootfs/standard/usr/share/mynode/mynode_app_versions.sh
UPGRADE_FILE=rootfs/standard/usr/bin/mynode_post_upgrade.sh
DOCKER_IMAGES_FILE=rootfs/standard/usr/bin/mynode_docker_images.sh
MARKETPLACE_DIR=rootfs/standard/usr/share/mynode_apps

# Variable prefixes, matching <APP>_VERSION in VERSIONS_FILE and <APP>_UPGRADE_URL in UPGRADE_FILE, DOCKER_IMAGES_FILE or VERSIONS_FILE
APPS="LNDHUB THUNDERHUB CARAVAN CORSPROXY JOININBOX BTCRPCEXPLORER CKBUNKER SPHINXRELAY PYBLOCK WARDENTERMINAL LOG2RAM"

# Marketplace app short names, using latest_version and download_source_url from their JSON
MARKETPLACE_APPS="astral datum lndboss lndg nostrrsrelay publicpool publicpoolui wetty"

# Docker images pulled by mynode_docker_images.sh: <pin variable> <image> <version variable, or a fixed tag>
DOCKER_IMAGES="
NETDATA_DIGEST netdata/netdata NETDATA_VERSION
MEMPOOL_FRONTEND_DIGEST mempool/frontend MEMPOOL_VERSION
MEMPOOL_BACKEND_DIGEST mempool/backend MEMPOOL_VERSION
MARIADB_DIGEST mariadb 10.9.3
LNBITS_DIGEST lnbits/lnbits LNBITS_VERSION
BTCPAYSERVER_GENERATOR_DIGEST btcpayserver/docker-compose-generator latest
"

# Docker images pulled by marketplace install scripts: <app> <pin variable> <image> <tag, with {VERSION} from its JSON>
MARKETPLACE_DOCKER_IMAGES="
albyhub IMAGE_DIGEST ghcr.io/getalby/hub {VERSION}
canary BACKEND_IMAGE_DIGEST schjonhaug/canary-backend {VERSION}
canary FRONTEND_IMAGE_DIGEST schjonhaug/canary-frontend {VERSION}
jam IMAGE_DIGEST ghcr.io/joinmarket-webui/jam-ui-only {VERSION}-clientserver-v0.9.11
lndboss IMAGE_DIGEST niteshbalusu/lndboss {VERSION}
"

# Toolchains and binaries installed as root by mynode_post_upgrade.sh and setup_device.sh, one pin
# per architecture where the download differs: <pin variable> <version variable> <URL, with {VERSION}>
TOOL_DOWNLOADS="
GO_ARMV6L_SHA256 GO_VERSION https://go.dev/dl/go{VERSION}.linux-armv6l.tar.gz
GO_ARM64_SHA256 GO_VERSION https://go.dev/dl/go{VERSION}.linux-arm64.tar.gz
GO_AMD64_SHA256 GO_VERSION https://go.dev/dl/go{VERSION}.linux-amd64.tar.gz
PYTHON_SHA256 PYTHON_VERSION https://www.python.org/ftp/python/{VERSION}/Python-{VERSION}.tar.xz
LNDCONNECT_ARMV7_SHA256 LNDCONNECT_VERSION https://github.com/LN-Zap/lndconnect/releases/download/{VERSION}/lndconnect-linux-armv7-{VERSION}.tar.gz
LNDCONNECT_AMD64_SHA256 LNDCONNECT_VERSION https://github.com/LN-Zap/lndconnect/releases/download/{VERSION}/lndconnect-linux-amd64-{VERSION}.tar.gz
TOR_SOURCE_SHA256 TOR_SOURCE_VERSION https://archive.torproject.org/tor-package-archive/tor-{VERSION}.tar.gz
UV_AARCH64_SHA256 UV_VERSION https://github.com/astral-sh/uv/releases/download/{VERSION}/uv-aarch64-unknown-linux-gnu.tar.gz
UV_X86_64_SHA256 UV_VERSION https://github.com/astral-sh/uv/releases/download/{VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz
"

CHECK=0
SELECTED=()
for ARG in "$@"; do
    if [ "$ARG" = "--check" ]; then
        CHECK=1
    else
        SELECTED+=("$ARG")
    fi
done

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

# Print a pin line with its status, counting pins that are missing or do not match
STALE=0
report () {
    local status
    status=$(status_of "$2" "$3")
    echo "$1    # $status"
    [ "$status" = "matches" ] || STALE=$((STALE + 1))
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
        report "${APP}_SHA256=\"$PINNED\"" "$CURRENT" "$PINNED"
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
    report "$APP: \"download_source_sha256\": \"$PINNED\"," "$CURRENT" "$PINNED"
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
        report "${VAR}=\"$PINNED\"" "$CURRENT" "$PINNED"
    done
done <<< "$DOCKER_IMAGES"

while read -r APP VAR IMAGE TAG_TEMPLATE; do
    [ -n "$APP" ] || continue
    wanted "$APP" || continue
    # The pin is in the JSON's install_env_vars if set there, otherwise in the install script
    IFS=$'\t' read -r VERSION JSON_PIN < <(python3 - "$MARKETPLACE_DIR/$APP/$APP.json" "$VAR" <<'EOF'
import json, sys
app = json.load(open(sys.argv[1]))
print("\t".join([app["latest_version"], (app.get("install_env_vars") or {}).get(sys.argv[2], "")]))
EOF
)
    TAG=${TAG_TEMPLATE//\{VERSION\}/$VERSION}
    DIGEST=$(digest_of "$IMAGE:$TAG")
    if [ -z "$DIGEST" ]; then
        echo "ERROR: could not get the digest of $IMAGE:$TAG" >&2
        exit 1
    fi
    PINNED="$TAG $DIGEST"
    if [ -n "$JSON_PIN" ]; then
        report "$APP: \"${VAR}\": \"$PINNED\"," "$JSON_PIN" "$PINNED"
    else
        CURRENT=$(grep -E "^[[:space:]]*${VAR}=\"" "$MARKETPLACE_DIR/$APP/scripts/install_$APP.sh" | head -1 | cut -d'"' -f2)
        report "$APP: ${VAR}=\"$PINNED\"" "$CURRENT" "$PINNED"
    fi
done <<< "$MARKETPLACE_DOCKER_IMAGES"

while read -r VAR VERSION_VAR URL_TEMPLATE; do
    [ -n "$VAR" ] || continue
    wanted "${VAR%%_*}" || continue
    VERSIONS=$(grep -E "^[[:space:]]*${VERSION_VAR}=\"[^\$\"]+\"" $VERSIONS_FILE | cut -d'"' -f2 | sort -u)
    if [ -z "$VERSIONS" ]; then
        echo "ERROR: could not determine version for $VAR" >&2
        exit 1
    fi
    for VERSION in $VERSIONS; do
        curl -fsSL "${URL_TEMPLATE//\{VERSION\}/$VERSION}" -o "$TMP_DIR/download" < /dev/null
        PINNED="$VERSION $(sha256_of "$TMP_DIR/download")"
        CURRENT=$(grep -E "^[[:space:]]*${VAR}=\"" $VERSIONS_FILE | grep -F "\"$VERSION " | head -1 | cut -d'"' -f2)
        report "${VAR}=\"$PINNED\"" "$CURRENT" "$PINNED"
    done
done <<< "$TOOL_DOWNLOADS"

# btcpayserver-docker has no releases; its setup script runs from a pinned commit
if wanted BTCPAYSERVER; then
    LATEST=$(git ls-remote https://github.com/btcpayserver/btcpayserver-docker HEAD < /dev/null | cut -f1)
    CURRENT=$(grep -E '^BTCPAYSERVER_DOCKER_COMMIT="' $VERSIONS_FILE | cut -d'"' -f2)
    echo "BTCPAYSERVER_DOCKER_COMMIT=\"$LATEST\"    # latest commit, $(status_of "$CURRENT" "$LATEST")"
fi

# A newer btcpayserver-docker commit is not a stale pin, so it is not counted
if [ "$CHECK" = "1" ] && [ "$STALE" -gt 0 ]; then
    echo "ERROR: $STALE pin(s) missing or not matching" >&2
    exit 1
fi
