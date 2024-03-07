#!/bin/bash

set -x
source /usr/share/mynode/mynode_app_versions.sh

# Delete old myNode .env file created before 0.12.x
if [ -f /usr/share/mynode/lnbits.env ]; then
    rm -f /usr/share/mynode/lnbits.env
fi

# if current LNbits version config is missign create .env from .env.example 
if [ ! -f /mnt/hdd/mynode/lnbits/update_config_$LNBITS_VERSION ]; then
    rm -f /mnt/hdd/mynode/lnbits/update_config_*
    touch /mnt/hdd/mynode/lnbits/update_config_$LNBITS_VERSION

    cp -f /opt/mynode/lnbits/.env.example /mnt/hdd/mynode/lnbits/.env
    chown bitcoin:bitcoin /mnt/hdd/mynode/lnbits/.env

# debug Disable
    sed -i "s|^DEBUG=.*|DEBUG=false|g" /mnt/hdd/mynode/lnbits/.env
# debug Enable
#   sed -i "s|^DEBUG=.*|DEBUG=true|g" /mnt/hdd/mynode/lnbits/.env
	
# ADMIN_UI Disable
    sed -i "s|^LNBITS_ADMIN_UI=.*|LNBITS_ADMIN_UI=false|g" /mnt/hdd/mynode/lnbits/.env
# ADMIN_UI Enable
#   sed -i "s|^LNBITS_ADMIN_UI=.*|LNBITS_ADMIN_UI=true|g" /mnt/hdd/mynode/lnbits/.env
	
# Update env with mynode lnd REST ip and port
    sed -i "s|^LND_REST_ENDPOINT=.*|LND_REST_ENDPOINT=https\:\/\/172.17.0.1:10080\/|g" /mnt/hdd/mynode/lnbits/.env

# Update env with files mapped in lnbits.service
    sed -i "s|^LND_REST_CERT=.*|LND_REST_CERT=\"/app/tls.cert\"|g" /mnt/hdd/mynode/lnbits/.env
    sed -i "s|^LND_REST_MACAROON=.*|LND_REST_MACAROON=\"/app/admin.macaroon\"|g" /mnt/hdd/mynode/lnbits/.env
fi



