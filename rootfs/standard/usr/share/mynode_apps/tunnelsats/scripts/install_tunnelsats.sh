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

set -e

echo "==================== INSTALLING APP ===================="

INSTALL_DIR="${INSTALL_FOLDER:-/opt/mynode/tunnelsats}"
STORAGE_DIR="${STORAGE_FOLDER:-/mnt/hdd/mynode/tunnelsats}"

if [ -L "$STORAGE_DIR" ]; then
    echo "ERROR: Refusing symlinked storage directory ${STORAGE_DIR}" >&2
    exit 1
fi
mkdir -p "$INSTALL_DIR"
mkdir -p "$STORAGE_DIR"
chmod 0700 "$STORAGE_DIR"

chmod +x "$INSTALL_DIR/bridge.py" 2>/dev/null || true

# Note: MyNode's application_info.py writes /home/bitcoin/.mynode/tunnelsats_version
# as root after install_tunnelsats.sh exits 0. Keep safe non-symlink fallback for manual runs.
APP_JSON="/usr/share/mynode_apps/tunnelsats/tunnelsats.json"
APP_VER="v1.0.1"
if [ -f "$APP_JSON" ] && command -v jq >/dev/null 2>&1; then
    APP_VER=$(jq -r '.latest_version // "v1.0.1"' "$APP_JSON" 2>/dev/null || echo "v1.0.1")
fi
if [ "$(id -u)" -eq 0 ] && id -u bitcoin >/dev/null 2>&1 && command -v runuser >/dev/null 2>&1; then
    runuser -u bitcoin -g bitcoin -- python3 - "$APP_VER" <<'PY' 2>/dev/null || true
import os, secrets, sys
ver = sys.argv[1]
for d in ("/home/bitcoin/.mynode", "/mnt/hdd/mynode/settings"):
    if not os.path.islink(d):
        os.makedirs(d, exist_ok=True)
    target = os.path.join(d, "tunnelsats_version")
    if os.path.islink(target):
        continue
    tmp = f"{target}.tmp.{secrets.token_hex(6)}"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(f"{ver}\n")
    os.replace(tmp, target)
PY
fi

echo "================== DONE INSTALLING APP ================="
