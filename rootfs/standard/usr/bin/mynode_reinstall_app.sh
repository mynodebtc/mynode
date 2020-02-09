#!/bin/bash

set -x
#set -e

source /usr/share/mynode/mynode_config.sh

# Make sure we have an app argument
if [ "$#" -ne 1 ]; then
    echo "Usage: mynode_reinstall_app.sh <app_name>"
    exit 1
fi
APP="$1" 

# Delete the app's version file so it will be re-installed
if [ "$APP" = "bitcoin" ]; then
    rm -f /home/bitcoin/.mynode/.btc_url
elif [ "$APP" = "lnd" ]; then
    rm -f /home/bitcoin/.mynode/.lnd_url
elif [ "$APP" = "loopd" ]; then
    rm -f /home/bitcoin/.mynode/.loop_url
elif [ "$APP" = "lndhub" ]; then
    rm -f /home/bitcoin/.mynode/.lndhub_url
elif [ "$APP" = "rtl" ]; then
    rm -f /home/bitcoin/.mynode/.rtl_url
elif [ "$APP" = "mempoolspace" ]; then
    rm -f /mnt/hdd/mynode/settings/mempoolspace_url
    systemctl stop mempoolspace
    docker rmi mempoolspace
elif [ "$APP" = "joinmarket" ]; then
    rm -f /home/bitcoin/.mynode/.joinmarket_url
elif [ "$APP" = "whirlpool" ]; then
    rm -f /home/bitcoin/.mynode/.whirlpool_url
elif [ "$APP" = "btcrpcexplorer" ]; then
    rm -f /home/bitcoin/.mynode/.btcrpcexplorer_url
elif [ "$APP" = "lndconnect" ]; then
    rm -f  /home/bitcoin/.mynode/.lndconnect_url
elif [ "$APP" = "webssh2" ]; then
    rm -f /mnt/hdd/mynode/settings/webssh2_url
    systemctl stop webssh2
    docker rmi webssh2
else
    echo "UNKNOWN APP: $APP"
    exit 1
fi

# Run post upgrade script
for i in {1..3}
do
    /bin/bash /usr/bin/mynode_post_upgrade.sh > /home/admin/upgrade_logs/reinstall_app_${APP}_post_${i}.txt 2>&1
    RC=$?
    if [ "${RC}" -eq "0" ]; then
        rm -f $UPGRADE_ERROR_FILE
        break
    fi
    sleep 10s
done
chown -R admin:admin /home/admin/upgrade_logs
sync