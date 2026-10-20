#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

# Update Bitcoin RPC Credentials
set +x
BTCRPCPW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)
NBXPLORER_VARIABLES_FILE=/mnt/hdd/mynode/btcpayserver/btcpayserver-docker/Generated/nbxplorer-variables.env
echo "NBXPLORER_BTCRPCUSER=mynode"            > $NBXPLORER_VARIABLES_FILE
echo "NBXPLORER_BTCRPCPASSWORD=$BTCRPCPW"    >> $NBXPLORER_VARIABLES_FILE
set -x

# BTCPay reads only these macaroons from LND's folder, so give it copies in a folder of its own
# (mounted at /etc/lnd_bitcoin by lnd.custom.yml). Refreshed on every start.
LND_MACAROON_DIR=/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet
BTCPAY_LND_DIR=/mnt/hdd/mynode/btcpayserver/lnd
BTCPAY_MACAROON_DIR=$BTCPAY_LND_DIR/data/chain/bitcoin/mainnet
mkdir -p $BTCPAY_MACAROON_DIR
chown -R root:root $BTCPAY_LND_DIR
chmod 700 $BTCPAY_LND_DIR
for macaroon in admin.macaroon readonly.macaroon invoice.macaroon; do
    if [ -f "$LND_MACAROON_DIR/$macaroon" ] && [ ! -L "$LND_MACAROON_DIR/$macaroon" ]; then
        install -m 600 -o root -g root "$LND_MACAROON_DIR/$macaroon" "$BTCPAY_MACAROON_DIR/$macaroon.tmp"
        mv -f "$BTCPAY_MACAROON_DIR/$macaroon.tmp" "$BTCPAY_MACAROON_DIR/$macaroon"
    else
        rm -f "$BTCPAY_MACAROON_DIR/$macaroon"
    fi
done

# BTCPay itself listens on 127.0.0.1:59392; nginx serves it on 49392 and 49393. btcpay-setup.sh
# writes the port into BTCPay's .env, so set it again on every start.
BTCPAY_ENV_FILE=/mnt/hdd/mynode/btcpayserver/.env
if [ -f "$BTCPAY_ENV_FILE" ]; then
    if grep -q '^NOREVERSEPROXY_HTTP_PORT=' "$BTCPAY_ENV_FILE"; then
        sed -i 's/^NOREVERSEPROXY_HTTP_PORT=.*/NOREVERSEPROXY_HTTP_PORT=127.0.0.1:59392/' "$BTCPAY_ENV_FILE"
    else
        echo "NOREVERSEPROXY_HTTP_PORT=127.0.0.1:59392" >> "$BTCPAY_ENV_FILE"
    fi
fi

# Compose files generated before these mounts changed still list the old ones. A new BTCPay
# version is generated from the updated fragments.
GENERATED_COMPOSE=/mnt/hdd/mynode/btcpayserver/btcpayserver-docker/Generated/docker-compose.generated.yml
if [ -f "$GENERATED_COMPOSE" ]; then
    sed -i -e '\#^[[:space:]]*-[[:space:]]*"\?/mnt/hdd/mynode/bitcoin:/root/\.bitcoin"\?[[:space:]]*$#d' \
           -e 's#"\?/mnt/hdd/mynode/lnd:/etc/lnd_bitcoin"\?[[:space:]]*$#"/mnt/hdd/mynode/btcpayserver/lnd:/etc/lnd_bitcoin:ro"#' \
           "$GENERATED_COMPOSE"
fi
