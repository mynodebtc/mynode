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

# Delete the app's version file so it will be re-installed
if [ "$APP" = "bitcoin" ]; then
    rm -f $BTC_VERSION_FILE
elif [ "$APP" = "lnd" ]; then
    rm -f $LND_VERSION_FILE
elif [ "$APP" = "loop" ]; then
    rm -f $LOOP_VERSION_FILE
elif [ "$APP" = "pool" ]; then
    rm -f $POOL_VERSION_FILE
elif [ "$APP" = "btcrpcexplorer" ]; then
    rm -f $BTCRPCEXPLORER_VERSION_FILE
elif [ "$APP" = "caravan" ]; then
    rm -f $CARAVAN_VERSION_FILE
elif [ "$APP" = "corsproxy" ]; then
    rm -f $CORSPROXY_VERSION_FILE
elif [ "$APP" = "joinmarket" ]; then
    rm -f $JOINMARKET_VERSION_FILE
elif [ "$APP" = "lnbits" ]; then
    rm -f $LNBITS_VERSION_FILE
elif [ "$APP" = "lndconnect" ]; then
    rm -f  $LNDCONNECT_VERSION_FILE
elif [ "$APP" = "lndhub" ]; then
    rm -f $LNDHUB_VERSION_FILE
elif [ "$APP" = "netdata" ]; then
    systemctl stop netdata
    docker rmi netdata/netdata || true
elif [ "$APP" = "mempoolspace" ]; then
    rm -f /mnt/hdd/mynode/settings/mempoolspace_url
    systemctl stop mempoolspace
    docker rmi mempoolspace
elif [ "$APP" = "btcpayserver" ]; then
    . "/opt/mynode/btcpayserver/btcpay-env.sh" && cd "$BTCPAY_BASE_DIRECTORY" && . helpers.sh && btcpay_remove
    cd ~
elif [ "$APP" = "rtl" ]; then
    rm -f $RTL_VERSION_FILE
elif [ "$APP" = "specter" ]; then
    rm -f $SPECTER_VERSION_FILE
elif [ "$APP" = "thunderhub" ]; then
    rm -f $THUNDERHUB_VERSION_FILE
elif [ "$APP" = "ckbunker" ]; then
    rm -f $CKBUNKER_VERSION_FILE
elif [ "$APP" = "sphinxrelay" ]; then
    rm -f $SPHINXRELAY_VERSION_FILE
elif [ "$APP" = "tor" ]; then
    apt-get remove -y tor
    apt-get install -y tor
elif [ "$APP" = "ufw" ]; then
    apt-get purge -y ufw
    apt-get install -y ufw
elif [ "$APP" = "webssh2" ]; then
    rm -f /mnt/hdd/mynode/settings/webssh2_url
    systemctl stop webssh2
    docker rmi webssh2
elif [ "$APP" = "whirlpool" ]; then
    rm -f $WHIRLPOOL_VERSION_FILE
elif [ "$APP" = "dojo" ]; then
    rm -f /mnt/hdd/mynode/settings/dojo_url
    cd /mnt/hdd/mynode/dojo/docker/my-dojo/

    # Stop and uninstall
    yes | ./dojo.sh uninstall

    # Reset config files
    cd ~
    rm -rf /opt/download/dojo
    rm -rf /mnt/hdd/mynode/dojo
else
    echo "UNKNOWN APP: $APP"
    exit 1
fi

# Run post upgrade script
for i in {1..3}
do
    /bin/bash /usr/bin/mynode_post_upgrade.sh 2>&1 | tee /home/admin/upgrade_logs/reinstall_app_${APP}_post_${i}.txt
    RC=$?
    if [ "${RC}" -eq "0" ]; then
        rm -f $UPGRADE_ERROR_FILE
        break
    fi
    sleep 10s
done
chown -R admin:admin /home/admin/upgrade_logs
sync