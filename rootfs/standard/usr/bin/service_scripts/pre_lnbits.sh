#!/bin/bash

set -x

# Copy config file
if [ ! -f /mnt/hdd/mynode/lnbits/.env ]; then
    cp /usr/share/mynode/lnbits.env /mnt/hdd/mynode/lnbits/.env
    chown bitcoin:bitcoin /mnt/hdd/mynode/lnbits/.env
fi

# Force update of LNBits config file (increment to force new update)
# LNBITS_CONFIG_UPDATE_NUM=1
# if [ ! -f /mnt/hdd/mynode/lnbits/update_config_$LNBITS_CONFIG_UPDATE_NUM ]; then
#     cp -f /usr/share/mynode/lnbits.env /mnt/hdd/mynode/lnbits/.env
#     chown bitcoin:bitcoin /mnt/hdd/mynode/lnbits/.env
#     touch /mnt/hdd/mynode/lnbits/update_config_$LNBITS_CONFIG_UPDATE_NUM
# fi

# Generate hex macaroons
#macaroonAdminHex=$(xxd -ps -u -c 1000 /mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon)

# Update env file
sed -i "s|^LNBITS_BACKEND_WALLET_CLASS=.*|LNBITS_BACKEND_WALLET_CLASS=LndRestWallet|g" /mnt/hdd/mynode/lnbits/.env
sed -i "s|^LND_REST_ENDPOINT=.*|LND_REST_ENDPOINT=https\:\/\/host.docker.internal\:10080\/|g" /mnt/hdd/mynode/lnbits/.env
#or sed -i "s|^LND_REST_ENDPOINT=.*|LND_REST_ENDPOINT=https\:\/\/172.17.0.1\:10080\/|g" /mnt/hdd/mynode/lnbits/.env
sed -i "s|^LND_REST_CERT=.*|LND_REST_CERT=\"/app/tls.cert\"|g" /mnt/hdd/mynode/lnbits/.env
sed -i "s|^LND_REST_MACAROON=.*|LND_REST_MACAROON=\"/app/admin.macaroon\"|g" /mnt/hdd/mynode/lnbits/.env
