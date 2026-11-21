#!/bin/bash
# Runs as root prior to launching tunnelsats.service (ExecStartPre=+)
set -euo pipefail
umask 077
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

APP_SHARE_DIR="/usr/share/mynode_apps/tunnelsats"
ROOT_SCRIPTS_DIR="${APP_SHARE_DIR}/root_scripts"
RECONCILE_ROOT_SRC="${ROOT_SCRIPTS_DIR}/reconcile_mynode.sh"
TS_SH_ROOT_SRC="${ROOT_SCRIPTS_DIR}/tunnelsats.sh"
RECONCILE_SBIN="/usr/local/sbin/tunnelsats-reconcile"
TS_SH_SBIN="/usr/local/sbin/tunnelsats"
STORAGE_DIR="/mnt/hdd/mynode/tunnelsats"
LEGACY_SUDOERS="/etc/sudoers.d/tunnelsats-reconcile"

# MyNode apps do not receive sudo privileges; remove any legacy v1.0.0 drop-in.
rm -f "$LEGACY_SUDOERS" 2>/dev/null || true

# Drop unnecessary bitcoin group membership so tunnelsats cannot read LND macaroons.
if id -u tunnelsats >/dev/null 2>&1; then
    gpasswd -d tunnelsats bitcoin >/dev/null 2>&1 || true
fi

if [ -L "$STORAGE_DIR" ]; then
    echo "ERROR: Refusing symlinked storage directory ${STORAGE_DIR}" >&2
    exit 1
fi
if id -u tunnelsats >/dev/null 2>&1; then
    install -d -o tunnelsats -g tunnelsats -m 0700 "$STORAGE_DIR"
else
    install -d -m 0700 "$STORAGE_DIR"
fi

install -d -o root -g root -m 0755 /run/tunnelsats /etc/tunnelsats

is_safe_root_file() {
    local f="$1"
    if [ -L "$f" ] || [ ! -f "$f" ]; then
        return 1
    fi
    local d
    d="$(dirname "$f")"
    if [ -L "$d" ] || [ ! -d "$d" ]; then
        return 1
    fi
    local f_meta d_meta
    f_meta="$(stat -c '%u:%g:%a' "$f" 2>/dev/null || echo "")"
    d_meta="$(stat -c '%u:%g:%a' "$d" 2>/dev/null || echo "")"
    case "$d_meta" in
        0:0:755|0:0:750|0:0:700) ;;
        *) return 1 ;;
    esac
    case "$f_meta" in
        0:0:755|0:0:750|0:0:700|0:0:644|0:0:640|0:0:600|0:0:555|0:0:500) return 0 ;;
        *) return 1 ;;
    esac
}

# Install root utilities exclusively from root-owned /usr/share/mynode_apps/tunnelsats/root_scripts
if is_safe_root_file "$TS_SH_ROOT_SRC"; then
    install -o root -g root -m 0755 "$TS_SH_ROOT_SRC" "${TS_SH_SBIN}.tmp.$$"
    mv -f "${TS_SH_SBIN}.tmp.$$" "$TS_SH_SBIN"
fi
if is_safe_root_file "$RECONCILE_ROOT_SRC"; then
    install -o root -g root -m 0755 "$RECONCILE_ROOT_SRC" "${RECONCILE_SBIN}.tmp.$$"
    mv -f "${RECONCILE_SBIN}.tmp.$$" "$RECONCILE_SBIN"
fi

if is_safe_root_file "$RECONCILE_SBIN" && [ -x "$RECONCILE_SBIN" ]; then
    "$RECONCILE_SBIN" boot-sync || true
fi

if [ -f /etc/tunnelsats/managed.json ] && [ ! -L /etc/tunnelsats/managed.json ]; then
    chmod 0755 /etc/tunnelsats 2>/dev/null || true
    chmod 0644 /etc/tunnelsats/managed.json 2>/dev/null || true
fi

APP_JSON="${APP_SHARE_DIR}/tunnelsats.json"
if [ -f "$APP_JSON" ] && [ ! -L "$APP_JSON" ] && [ -d /home/bitcoin/.mynode ] && [ ! -L /home/bitcoin/.mynode ] && [ ! -e /home/bitcoin/.mynode/tunnelsats_version ]; then
    APP_VER="v1.0.1"
    if command -v jq >/dev/null 2>&1; then
        APP_VER=$(jq -r '.latest_version // "v1.0.1"' "$APP_JSON" 2>/dev/null || echo "v1.0.1")
    fi
    if id -u bitcoin >/dev/null 2>&1 && command -v runuser >/dev/null 2>&1; then
        runuser -u bitcoin -g bitcoin -- python3 - "$APP_VER" <<'PY' 2>/dev/null || true
import os, secrets, sys
ver = sys.argv[1]
target = "/home/bitcoin/.mynode/tunnelsats_version"
if os.path.islink(target):
    sys.exit(1)
tmp = f"{target}.tmp.{secrets.token_hex(6)}"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    f.write(f"{ver}\n")
os.replace(tmp, target)
PY
    fi
    rm -f /tmp/app_cache.json 2>/dev/null || true
fi
