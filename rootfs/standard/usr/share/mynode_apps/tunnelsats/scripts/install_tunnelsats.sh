#!/bin/bash
# shellcheck disable=SC1091

if [ -f /usr/share/mynode/mynode_device_info.sh ]; then
    source /usr/share/mynode/mynode_device_info.sh
fi
if [ -f /usr/share/mynode/mynode_app_versions.sh ]; then
    source /usr/share/mynode/mynode_app_versions.sh
fi
if [ -f /usr/share/mynode/mynode_functions.sh ]; then
    source /usr/share/mynode/mynode_functions.sh
fi

set -x
set -e

echo "==================== INSTALLING APP ===================="

INSTALL_DIR="${INSTALL_FOLDER:-/opt/mynode/tunnelsats}"
STORAGE_DIR="${STORAGE_FOLDER:-/mnt/hdd/mynode/tunnelsats}"

mkdir -p "$INSTALL_DIR"
mkdir -p "$STORAGE_DIR"
chmod 0700 "$STORAGE_DIR"

chmod +x "$INSTALL_DIR/bridge.py" 2>/dev/null || true
chmod +x "$INSTALL_DIR/scripts/"*.sh 2>/dev/null || true

APP_JSON="/usr/share/mynode_apps/tunnelsats/tunnelsats.json"
APP_VER="v1.0.0"
if [ -f "$APP_JSON" ] && command -v jq >/dev/null 2>&1; then
    APP_VER=$(jq -r '.latest_version // "v1.0.0"' "$APP_JSON" 2>/dev/null || echo "v1.0.0")
fi
mkdir -p /home/bitcoin/.mynode /mnt/hdd/mynode/settings 2>/dev/null || true
printf '%s\n' "$APP_VER" > /home/bitcoin/.mynode/tunnelsats_version 2>/dev/null || true
printf '%s\n' "$APP_VER" > /mnt/hdd/mynode/settings/tunnelsats_version 2>/dev/null || true
chown bitcoin:bitcoin /home/bitcoin/.mynode/tunnelsats_version /mnt/hdd/mynode/settings/tunnelsats_version 2>/dev/null || true
rm -f /tmp/app_cache.json 2>/dev/null || true

echo "================== DONE INSTALLING APP ================="
