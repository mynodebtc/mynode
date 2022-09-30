#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

# Copy TLS cert
cp -f /mnt/hdd/mynode/lnd/tls.cert /opt/mynode/lnbits/

# Generate hex macaroons
macaroonAdminHex=$(xxd -ps -u -c 1000 /mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon)

# Update env file
sed -i "s/^LND_REST_MACAROON=.*/LND_REST_MACAROON=${macaroonAdminHex}/g" /opt/mynode/lnbits/.env
#sed -i "s/^LND_REST_INVOICE_MACAROON=.*/LND_REST_INVOICE_MACAROON=${macaroonInvoiceHex}/g" /opt/mynode/lnbits/.env
#sed -i "s/^LND_REST_READ_MACAROON=.*/LND_REST_READ_MACAROON=${macaroonReadHex}/g" /opt/mynode/lnbits/.env
