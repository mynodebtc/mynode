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

if [ "$(id -u)" -eq 0 ]; then
    if [ -x /usr/local/sbin/tunnelsats-reconcile ]; then
        /usr/local/sbin/tunnelsats-reconcile uninstall || true
    elif [ -f /opt/mynode/tunnelsats/scripts/reconcile_mynode.sh ]; then
        /bin/bash /opt/mynode/tunnelsats/scripts/reconcile_mynode.sh uninstall || true
    fi
    rm -f /opt/mynode/ts-mynode || true
else
    sudo -n /usr/local/sbin/tunnelsats-reconcile uninstall || true
fi

rm -f /home/bitcoin/.mynode/tunnelsats_version /mnt/hdd/mynode/settings/tunnelsats_version /tmp/app_cache.json 2>/dev/null || true

echo "================== DONE UNINSTALLING APP ================="
