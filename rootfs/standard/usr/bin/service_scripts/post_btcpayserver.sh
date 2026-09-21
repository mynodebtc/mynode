#!/bin/bash

source /usr/share/mynode/mynode_functions.sh

set -x

BTCPAY_DIR=/mnt/hdd/mynode/btcpayserver
BTCPAY_PASSWORD_TOOL="/usr/local/bin/python3 /usr/share/mynode/btcpay_password.py"

# Take the BTCPay administrator account before anything else on the network can. Until a server
# admin exists, BTCPay lets whoever asks first create one - through its registration page and
# through POST /api/v1/users, neither of which needs a login - and a server admin can spend from
# the node's lightning wallet. Creating it here also leaves registration locked, which BTCPay
# does itself once the first administrator exists.

if is_app_password_user_set btcpayserver; then
    # The user manages this login themselves
    exit 0
fi

if has_app_password btcpayserver; then
    # Stop showing the saved password once it is no longer the account's, which means the user
    # changed it in BTCPay itself
    set +x
    $BTCPAY_PASSWORD_TOOL check < "$BTCPAY_DIR/.app_password"
    case $? in
        0) ;;                                         # still the password MyNode set
        1) save_app_password_user_set btcpayserver ;;  # changed in BTCPay
        *) echo "Could not read BTCPay's database, leaving the saved password alone" ;;
    esac
    set -x
    exit 0
fi

# Wait for the API to answer - BTCPay brings up a container stack, so this takes a while
for _ in $(seq 1 150); do
    if curl -s -o /dev/null --max-time 5 http://127.0.0.1:49392/api/v1/server/info; then
        break
    fi
    sleep 4
done

set +x
BTCPAY_PASSWORD=$(generate_app_password)
PASSWORD_OWNER=$(printf '%s' "$BTCPAY_PASSWORD" | $BTCPAY_PASSWORD_TOOL set)

if [ "$PASSWORD_OWNER" = "mynode" ]; then
    save_app_default_password btcpayserver "$BTCPAY_PASSWORD"
elif [ "$PASSWORD_OWNER" = "user" ]; then
    save_app_password_user_set btcpayserver
else
    set -x
    echo "ERROR: BTCPay administrator account was not set up"
fi
unset BTCPAY_PASSWORD
set -x
