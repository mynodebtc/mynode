#!/bin/bash

set -x
#set -e

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_app_versions.sh

# Make sure we have an app argument
if [ "$#" -ne 1 ]; then
    echo "Usage: mynode_reinstall_app.sh <app_name>"
    exit 1
fi
APP="$1"

# Shut down main services to save memory and CPU and stop app being reinstalled
/usr/bin/mynode_stop_critical_services.sh

# Delete the app's version file and install file
rm -f /home/bitcoin/.mynode/${APP}_version || true
rm -f /mnt/hdd/mynode/settings/${APP}_version || true
rm -f /home/bitcoin/.mynode/install_${APP} || true
rm -f /mnt/hdd/mynode/settings/install_${APP} || true
sync

# Attempt generic uninstall
rm -rf /opt/mynode/${APP}

# Custom uninstall steps
if [ "$APP" = "btcrpcexplorer" ]; then
    rm -rf /opt/mynode/btc-rpc-explorer
elif [ "$APP" = "lndhub" ]; then
    rm -rf /opt/mynode/LndHub
elif [ "$APP" = "rtl" ]; then
    m -rf /opt/mynode/RTL
else
    echo "No custom uninstall steps"
fi


chown -R admin:admin /home/admin/upgrade_logs
sync