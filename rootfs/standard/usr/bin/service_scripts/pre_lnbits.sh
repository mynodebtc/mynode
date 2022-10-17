#!/bin/bash

set -x


# Generate hex macaroons
#macaroonAdminHex=$(xxd -ps -u -c 1000 /mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon)

# Update env file
sed -i "s|^LND_REST_MACAROON=.*|LND_REST_MACAROON=\"/app/admin.macaroon\"|g" /opt/mynode/lnbits/.env
