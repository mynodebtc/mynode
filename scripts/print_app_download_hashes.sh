#!/bin/bash

# Print the sha256 of app downloads that have no upstream signature or checksum. Run from the
# repository root after changing one of these app versions, and paste each line over the
# matching pin:
#   - built-in apps: <APP>_SHA256 in rootfs/standard/usr/share/mynode/mynode_app_versions.sh
#   - marketplace apps: "download_source_sha256" in rootfs/standard/usr/share/mynode_apps/<app>/<app>.json
# Pass app names (e.g. THUNDERHUB lndg) to check only those.

set -e

VERSIONS_FILE=rootfs/standard/usr/share/mynode/mynode_app_versions.sh
UPGRADE_FILE=rootfs/standard/usr/bin/mynode_post_upgrade.sh
MARKETPLACE_DIR=rootfs/standard/usr/share/mynode_apps

# Variable prefixes, matching <APP>_VERSION in VERSIONS_FILE and <APP>_UPGRADE_URL in UPGRADE_FILE or VERSIONS_FILE
APPS="LNDHUB THUNDERHUB CARAVAN CORSPROXY JOININBOX BTCRPCEXPLORER CKBUNKER SPHINXRELAY PYBLOCK WARDENTERMINAL LOG2RAM"

# Marketplace app short names, using latest_version and download_source_url from their JSON
MARKETPLACE_APPS="astral lilywallet lndboss lndg nostrrsrelay publicpool publicpoolui wetty"

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
    URL_TEMPLATE=$(grep -h -m1 "${APP}_UPGRADE_URL=" $UPGRADE_FILE $VERSIONS_FILE | head -1 | sed 's/^ *//' | cut -d= -f2-)
    # Every literal version, including overrides for older systems
    VERSIONS=$(grep -E "^[[:space:]]*${APP}_VERSION=\"[^\$\"]+\"" $VERSIONS_FILE | cut -d'"' -f2)
    if [ -z "$VERSIONS" ] || [ -z "$URL_TEMPLATE" ]; then
        echo "ERROR: could not determine version or URL for $APP" >&2
        exit 1
    fi

    for VERSION in $VERSIONS; do
        URL=${URL_TEMPLATE//\$${APP}_VERSION/$VERSION}
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
