#!/bin/bash

set -x
#set -e

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_app_versions.sh
source /usr/share/mynode/mynode_functions.sh

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

# A reinstalled app gets a new generated login password on its next start. Alby Hub keeps its
# data across a reinstall, and its password with it.
if [ "$APP" != "albyhub" ]; then
    rm -f /mnt/hdd/mynode/${APP}/.app_password || true
fi

# Make sure app is marked for install
if [ -f /home/bitcoin/.mynode/${APP}_version_latest ]; then
    touch /home/bitcoin/.mynode/install_${APP} || true
elif [ -f /mnt/hdd/mynode/settings/${APP}_version_latest ]; then
    touch /mnt/hdd/mynode/settings/install_${APP} || true
else
    # App is probably dynamic app (no version_latest file) so go ahead and mark sd card
    touch /home/bitcoin/.mynode/install_${APP} || true
fi

# Remove a leftover container named after the app, which blocks the next start and image removal
docker rm -f "$APP" 2>/dev/null || true

# Custom re-install steps
if [ "$APP" = "bos" ]; then
    npm uninstall -g balanceofsatoshis
elif [ "$APP" = "netdata" ]; then
    systemctl stop netdata
    # Remove leftover containers, which can point at a deleted Docker network
    if [ -f /opt/mynode/netdata/netdata-compose.yml ]; then
        docker-compose -f /opt/mynode/netdata/netdata-compose.yml down --remove-orphans
    fi
    remove_docker_images_by_name 'netdata'
elif [ "$APP" = "btcpayserver" ]; then
    # Stop and clean images
    /usr/local/bin/btcpay-down.sh
    #/usr/local/bin/btcpay-clean.sh # This removes WAY too much!
    remove_docker_images_by_name 'btcpayserver/btcpayserver'
    remove_docker_images_by_name 'nicolasdorier/nbxplorer'
    remove_docker_images_by_name 'btcpayserver/postgres'

    # Remove files and data (don't remove volume for re-install)
    rm -f /etc/profile.d/btcpay-env.sh
    rm -rf /usr/local/bin/btcpay-*
    rm -rf /usr/local/bin/changedomain.sh

    # Finally remove main folder
    rm -rf /mnt/hdd/mynode/btcpayserver
elif [ "$APP" = "docker" ]; then
    apt-get install --reinstall docker-ce
elif [ "$APP" = "tor" ]; then
    apt-get remove -y tor
    apt-get install -y tor
elif [ "$APP" = "nodejs" ]; then
    # This will force a re-install of node + node based apps in the post upgrade script
    echo "" > /etc/apt/sources.list.d/nodesource.list
    rm -f /etc/apt/sources.list.d/nodesource.sources
elif [ "$APP" = "ufw" ]; then
    apt-get purge -y ufw
    apt-get install -y ufw
elif [ "$APP" = "vpn" ]; then
    rm -rf /etc/openvpn
    rm -rf /etc/.pivpn
    rm -rf /home/pivpn/ovpns
elif [ "$APP" = "dojo" ]; then
    rm -f /mnt/hdd/mynode/settings/dojo_url
    rm -f /mnt/hdd/mynode/settings/mynode_dojo_install
    cd /mnt/hdd/mynode/dojo/docker/my-dojo/

    # Stop and uninstall
    ./dojo.sh uninstall --auto
    ./dojo.sh clean

    # Reset config files
    cd ~
    rm -rf /opt/download/dojo
    rm -rf /mnt/hdd/mynode/dojo
elif [ "$APP" = "lndmanage" ]; then
    rm -f /usr/local/bin/lndmanage
    rm -rf /usr/local/lib/mynode/venv/lndmanage
    /usr/local/bin/python3 -m pip uninstall -y lndmanage
elif [ "$APP" = "mempool" ]; then
    cd /mnt/hdd/mynode/mempool
    # Remove leftover containers, which can point at a deleted Docker network
    docker-compose down --remove-orphans
    rm -rf data
    rm -rf mysql/data
    cd ~
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