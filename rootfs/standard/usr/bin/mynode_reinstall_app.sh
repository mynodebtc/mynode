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

# Shut down main services to save memory and CPU and stop app being reinstalled
/usr/bin/mynode_stop_critical_services.sh

# Delete the app's version file so it will be re-installed
if [ "$APP" = "bitcoin" ]; then
    rm -f /home/bitcoin/.mynode/.btc_url
elif [ "$APP" = "lnd" ]; then
    rm -f /home/bitcoin/.mynode/.lnd_url
elif [ "$APP" = "loopd" ]; then
    rm -f /home/bitcoin/.mynode/.loop_url
elif [ "$APP" = "btcrpcexplorer" ]; then
    rm -f /home/bitcoin/.mynode/.btcrpcexplorer_url
elif [ "$APP" = "caravan" ]; then
    rm -f /home/bitcoin/.mynode/.caravan_url
elif [ "$APP" = "joinmarket" ]; then
    rm -f /home/bitcoin/.mynode/.joinmarket_url
elif [ "$APP" = "lnbits" ]; then
    rm -f /home/bitcoin/.mynode/.lnbits_url
elif [ "$APP" = "lndconnect" ]; then
    rm -f  /home/bitcoin/.mynode/.lndconnect_url
elif [ "$APP" = "lndhub" ]; then
    rm -f /home/bitcoin/.mynode/.lndhub_url
elif [ "$APP" = "netdata" ]; then
    systemctl stop netdata
    docker rmi netdata/netdata || true
elif [ "$APP" = "mempoolspace" ]; then
    rm -f /mnt/hdd/mynode/settings/mempoolspace_url
    systemctl stop mempoolspace
    docker rmi mempoolspace
elif [ "$APP" = "rtl" ]; then
    rm -f /home/bitcoin/.mynode/.rtl_url
elif [ "$APP" = "specter" ]; then
    rm -f /home/bitcoin/.mynode/.spectre_url
elif [ "$APP" = "thunderhub" ]; then
    rm -f /home/bitcoin/.mynode/.thunderhub_url
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
    rm -f /home/bitcoin/.mynode/.whirlpool_url
elif [ "$APP" = "dojo" ]; then
    rm -f /mnt/hdd/mynode/settings/dojo_url
    cd /opt/mynode/dojo/docker/my-dojo/

    # Stop and uninstall
    yes | ./dojo.sh uninstall

    # Reset config files
    cd ~
    rm -rf /opt/mynode/.dojo
    rm -rf /opt/mynode/dojo
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