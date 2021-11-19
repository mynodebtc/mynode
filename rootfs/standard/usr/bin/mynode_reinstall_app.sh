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
rm -f /home/bitcoin/.mynode/${APP}_version || true
rm -f /mnt/hdd/mynode/settings/${APP}_version || true

# Make sure app is marked for install
if [ -f /home/bitcoin/.mynode/${APP}_version_latest ]; then
    touch /home/bitcoin/.mynode/install_${APP} || true
else
    touch /mnt/hdd/mynode/settings/install_${APP} || true
fi

# Custom re-install steps
if [ "$APP" = "bos" ]; then
    npm uninstall -g balanceofsatoshis
elif [ "$APP" = "netdata" ]; then
    systemctl stop netdata
    docker rmi netdata/netdata || true
elif [ "$APP" = "btcpayserver" ]; then
    . "/opt/mynode/btcpayserver/btcpay-env.sh" && cd "$BTCPAY_BASE_DIRECTORY" && . helpers.sh && btcpay_remove
    cd ~
elif [ "$APP" = "tor" ]; then
    apt-get remove -y tor
    apt-get install -y tor
elif [ "$APP" = "ufw" ]; then
    apt-get purge -y ufw
    apt-get install -y ufw
elif [ "$APP" = "webssh2" ]; then
    rm -f /mnt/hdd/mynode/settings/webssh2_version
    systemctl stop webssh2
    docker rmi webssh2
elif [ "$APP" = "vpn" ]; then
    rm -rf /etc/openvpn
    rm -rf /etc/.pivpn
    rm -rf /home/pivpn/ovpns
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
elif [ "$APP" = "lndmanage" ]; then
    pip3 uninstall -y lndmanage
else
    echo "No custom re-install steps"
fi

# Run post upgrade script
for i in {1..3}
do
    /bin/bash /usr/bin/mynode_post_upgrade.sh 2>&1
    RC=$?
    if [ "${RC}" -eq "0" ]; then
        rm -f $UPGRADE_ERROR_FILE
        break
    fi
    printf "\n\n\n"
    printf "##################################################\n"
    printf "Post upgrade script failed attempt $i. Retrying.  \n"
    printf "##################################################\n"
    printf "\n\n\n"
    sleep 10s
done
chown -R admin:admin /home/admin/upgrade_logs
sync