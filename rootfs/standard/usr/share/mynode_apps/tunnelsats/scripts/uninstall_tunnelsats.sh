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

echo "==================== UNINSTALLING APP ===================="

STORAGE_DIR="${STORAGE_FOLDER:-/mnt/hdd/mynode/tunnelsats}"
DESIRED_STATE_FILE="${STORAGE_DIR}/desired-state.json"

# Note: MyNode runs uninstall_<app>.sh as the unprivileged app user (tunnelsats).
# Host-level dataplane teardown runs as root via MyNode's disable_actions /
# mynode_uninstall_app.sh hooks calling /usr/share/mynode_apps/tunnelsats/root_scripts/reconcile_mynode.sh.
# If invoked directly as root during manual maintenance, execute only the root-owned binary.
if [ "$(id -u)" -eq 0 ]; then
    if [ -f /usr/local/sbin/tunnelsats-reconcile ] && [ ! -L /usr/local/sbin/tunnelsats-reconcile ] && [ "$(stat -c '%u:%g' /usr/local/sbin/tunnelsats-reconcile 2>/dev/null)" = "0:0" ]; then
        /usr/local/sbin/tunnelsats-reconcile uninstall || true
    elif [ -f /usr/share/mynode_apps/tunnelsats/root_scripts/reconcile_mynode.sh ] && [ ! -L /usr/share/mynode_apps/tunnelsats/root_scripts/reconcile_mynode.sh ]; then
        /bin/bash /usr/share/mynode_apps/tunnelsats/root_scripts/reconcile_mynode.sh uninstall || true
    fi
    rm -f /home/bitcoin/.mynode/tunnelsats_version /mnt/hdd/mynode/settings/tunnelsats_version /tmp/app_cache.json 2>/dev/null || true
elif [ -d "$STORAGE_DIR" ] && [ ! -L "$STORAGE_DIR" ]; then
    if [ ! -L "$DESIRED_STATE_FILE" ]; then
        tmp_desired="${DESIRED_STATE_FILE}.tmp.$$"
        if [ ! -e "$tmp_desired" ] && [ ! -L "$tmp_desired" ]; then
            if printf '{"version":1,"desired":"tor-only","reason":"uninstall"}\n' > "$tmp_desired" 2>/dev/null; then
                chmod 0600 "$tmp_desired" 2>/dev/null || true
                mv -f "$tmp_desired" "$DESIRED_STATE_FILE" 2>/dev/null || rm -f "$tmp_desired" 2>/dev/null || true
            fi
        fi
    fi
fi

echo "================== DONE UNINSTALLING APP ================="
