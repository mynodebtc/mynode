#!/bin/bash

# Bake the LND macaroon for an app, limited to the calls that app makes. The permission list
# for every app is kept here, so apps are handed a macaroon rather than baking their own. Runs
# as root from the app's service, before the app starts.
#
# Each app has its own root key ID. The old root key is deleted before baking, which revokes
# every macaroon baked for the app before, including ones baked with an older permission list.
#
# Usage: mynode_bake_app_macaroon.sh <app>
# Writes /mnt/hdd/mynode/lnd/<app>.macaroon. LND must be running with its wallet unlocked.

source /usr/share/mynode/mynode_config.sh

APP="$1"

# Root key IDs start at 0x6d796e6f00000000 ("myno"), well away from IDs a user might pick
case "$APP" in
    lnbits)
        ROOT_KEY_ID=7888457645336559617
        PERMISSIONS=(
            uri:/lnrpc.Lightning/ChannelBalance
            uri:/lnrpc.Lightning/AddInvoice
            uri:/lnrpc.Lightning/LookupInvoice
            uri:/lnrpc.Lightning/SubscribeInvoices
            uri:/routerrpc.Router/SendPaymentV2
            uri:/routerrpc.Router/TrackPaymentV2
            uri:/invoicesrpc.Invoices/AddHoldInvoice
            uri:/invoicesrpc.Invoices/SettleInvoice
            uri:/invoicesrpc.Invoices/CancelInvoice
        )
        ;;
    sphinxrelay)
        # The relay uses this for its signer, router and wallet calls too
        ROOT_KEY_ID=7888457645336559618
        PERMISSIONS=(
            uri:/lnrpc.Lightning/GetInfo
            uri:/lnrpc.Lightning/ChannelBalance
            uri:/lnrpc.Lightning/ListChannels
            uri:/lnrpc.Lightning/PendingChannels
            uri:/lnrpc.Lightning/GetChanInfo
            uri:/lnrpc.Lightning/QueryRoutes
            uri:/lnrpc.Lightning/ListPeers
            uri:/lnrpc.Lightning/ConnectPeer
            uri:/lnrpc.Lightning/AddInvoice
            uri:/lnrpc.Lightning/LookupInvoice
            uri:/lnrpc.Lightning/ListInvoices
            uri:/lnrpc.Lightning/SubscribeInvoices
            uri:/lnrpc.Lightning/ListPayments
            uri:/lnrpc.Lightning/SignMessage
            uri:/lnrpc.Lightning/VerifyMessage
            uri:/lnrpc.Lightning/NewAddress
            uri:/lnrpc.Lightning/UpdateChannelPolicy
            uri:/routerrpc.Router/SendPaymentV2
            uri:/signrpc.Signer/SignMessage
            uri:/signrpc.Signer/VerifyMessage
            uri:/walletrpc.WalletKit/ListUnspent
        )
        ;;
    albyhub)
        # Alby Hub is a full node manager, so this covers channels and on-chain funds. It
        # leaves out the macaroon permissions, so the hub cannot bake or revoke macaroons.
        ROOT_KEY_ID=7888457645336559619
        PERMISSIONS=(
            uri:/lnrpc.Lightning/GetInfo
            uri:/lnrpc.Lightning/GetDebugInfo
            uri:/lnrpc.Lightning/ListChannels
            uri:/lnrpc.Lightning/PendingChannels
            uri:/lnrpc.Lightning/GetTransactions
            uri:/lnrpc.Lightning/AddInvoice
            uri:/lnrpc.Lightning/SubscribeInvoices
            uri:/lnrpc.Lightning/ListInvoices
            uri:/lnrpc.Lightning/LookupInvoice
            uri:/lnrpc.Lightning/DescribeGraph
            uri:/lnrpc.Lightning/GetNodeInfo
            uri:/lnrpc.Lightning/GetChanInfo
            uri:/lnrpc.Lightning/SignMessage
            uri:/lnrpc.Lightning/ConnectPeer
            uri:/lnrpc.Lightning/ListPeers
            uri:/lnrpc.Lightning/DisconnectPeer
            uri:/lnrpc.Lightning/OpenChannelSync
            uri:/lnrpc.Lightning/CloseChannel
            uri:/lnrpc.Lightning/WalletBalance
            uri:/lnrpc.Lightning/SendCoins
            uri:/lnrpc.Lightning/NewAddress
            uri:/lnrpc.Lightning/UpdateChannelPolicy
            uri:/lnrpc.Lightning/SubscribeChannelEvents
            uri:/lnrpc.Lightning/ForwardingHistory
            uri:/routerrpc.Router/SendPaymentV2
            uri:/routerrpc.Router/TrackPayments
            uri:/invoicesrpc.Invoices/AddHoldInvoice
            uri:/invoicesrpc.Invoices/SettleInvoice
            uri:/invoicesrpc.Invoices/CancelInvoice
            uri:/invoicesrpc.Invoices/SubscribeSingleInvoice
        )
        ;;
    *)
        echo "No LND macaroon permissions defined for app: $APP"
        exit 1
        ;;
esac

NETWORK=mainnet
if [ -f $IS_TESTNET_ENABLED_FILE ]; then
    NETWORK=testnet
fi
LNCLI="lncli --network=$NETWORK --lnddir /mnt/hdd/mynode/lnd"

MACAROON=/mnt/hdd/mynode/lnd/$APP.macaroon
rm -f $MACAROON.tmp

if ! $LNCLI deletemacaroonid $ROOT_KEY_ID > /dev/null; then
    echo "Failed to revoke the old $APP macaroon"
    exit 1
fi
$LNCLI bakemacaroon --root_key_id $ROOT_KEY_ID --save_to $MACAROON.tmp "${PERMISSIONS[@]}"
if [ ! -s $MACAROON.tmp ]; then
    echo "Failed to create $APP macaroon"
    exit 1
fi
chown bitcoin:bitcoin $MACAROON.tmp
chmod 600 $MACAROON.tmp
mv -f $MACAROON.tmp $MACAROON

exit 0
