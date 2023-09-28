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
sed -i "s|^LND_REST_MACAROON=.*|LND_REST_MACAROON=\"/app/admin.macaroon\"|g" /mnt/hdd/mynode/lnbits/.env
