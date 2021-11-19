#!/bin/bash

set -x
#set -e

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_app_versions.sh

# Make sure we have an app argument
if [ "$#" -ne 1 ]; then
    echo "Usage: mynode_uninstall_app.sh <app_name>"
    exit 1
fi
APP="$1"


# Delete the app's version file and install file
rm -f /home/bitcoin/.mynode/${APP}_version || true
rm -f /mnt/hdd/mynode/settings/${APP}_version || true
rm -f /home/bitcoin/.mynode/install_${APP} || true
rm -f /mnt/hdd/mynode/settings/install_${APP} || true
sync

# Custom uninstall steps
if [ "$APP" = "bos" ]; then
    npm uninstall -g balanceofsatoshis
elif [ "$APP" = "btcpayserver" ]; then
    . "/opt/mynode/btcpayserver/btcpay-env.sh" && cd "$BTCPAY_BASE_DIRECTORY" && . helpers.sh && btcpay_remove
    cd ~
elif [ "$APP" = "btcrpcexplorer" ]; then
    rm -rf /opt/mynode/btc-rpc-explorer
elif [ "$APP" = "dojo" ]; then
    rm -f /mnt/hdd/mynode/settings/dojo_url
    rm -f /mnt/hdd/mynode/settings/mynode_dojo_install
    cd /mnt/hdd/mynode/dojo/docker/my-dojo/

    # Stop and uninstall
    yes | ./dojo.sh uninstall

    # Reset config files
    cd ~
    rm -rf /opt/download/dojo
    rm -rf /mnt/hdd/mynode/dojo
elif [ "$APP" = "joininbox" ]; then
    rm -rf /home/joinmarket/*
    rm -rf /home/joinmarket/joininbox-*
    rm -rf /home/joinmarket/.cache
elif [ "$APP" = "lndhub" ]; then
    rm -rf /opt/mynode/LndHub
elif [ "$APP" = "lndmanage" ]; then
    pip3 uninstall -y lndmanage
elif [ "$APP" = "rtl" ]; then
    rm -rf /opt/mynode/RTL
else
    echo "No custom uninstall steps"
fi

# Attempt generic uninstall
rm -rf /opt/mynode/${APP}


chown -R admin:admin /home/admin/upgrade_logs
sync