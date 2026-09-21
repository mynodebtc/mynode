#!/bin/bash

source /usr/share/mynode/mynode_functions.sh

set -x

LNBITS_DIR=/mnt/hdd/mynode/lnbits

# Copy config file
if [ ! -f $LNBITS_DIR/.env ]; then
    cp /usr/share/mynode/lnbits.env $LNBITS_DIR/.env
    chown bitcoin:bitcoin $LNBITS_DIR/.env
fi

# Force update of LNBits config file (increment to force new update)
LNBITS_CONFIG_UPDATE_NUM=1
if [ ! -f $LNBITS_DIR/update_config_$LNBITS_CONFIG_UPDATE_NUM ]; then
    cp -f /usr/share/mynode/lnbits.env $LNBITS_DIR/.env
    chown bitcoin:bitcoin $LNBITS_DIR/.env
    touch $LNBITS_DIR/update_config_$LNBITS_CONFIG_UPDATE_NUM
fi

# Make folder for persistent extensions
if [ ! -d "$LNBITS_DIR/extensions" ]; then
    mkdir -p "$LNBITS_DIR/extensions"
fi

# Generate hex macaroons
#macaroonAdminHex=$(xxd -ps -u -c 1000 /mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon)

# Update env file
sed -i "s|^LND_REST_MACAROON=.*|LND_REST_MACAROON=\"/app/admin.macaroon\"|g" $LNBITS_DIR/.env

# Give the super user account a login before LNbits starts listening. Until the account has a
# password, LNbits sends every request to its first install page, and that page's API needs no
# login, so whoever opens LNbits first chooses the super user's credentials.
#
# The database is owned by root and the bcrypt LNbits hashes with is only in the image, so the
# account is read and written from inside it (see lnbits_password.py). LNbits keeps its packages
# in a virtualenv, and older versions in the system Python. Passwords go in on stdin, never in the
# arguments or the container config, which anyone in the docker group can read.
LNBITS_PASSWORD_ARGS=(--rm -i
    --volume $LNBITS_DIR/:/app/data
    --volume /usr/share/mynode/lnbits_password.py:/app/lnbits_password.py:ro
    --entrypoint sh lnbits -c
    'PYTHON=/app/.venv/bin/python; [ -x "$PYTHON" ] || PYTHON=python3; exec "$PYTHON" /app/lnbits_password.py "$1"'
    lnbits_password)

if is_app_password_user_set lnbits; then
    # The user set their own password, so MyNode no longer manages it
    :
elif has_app_password lnbits && [ -f "$LNBITS_DIR/database.sqlite3" ]; then
    set -e

    # Stop showing the saved password on the app page once it stops working, which means the
    # user changed it in LNbits itself
    set +x
    if ! docker run "${LNBITS_PASSWORD_ARGS[@]}" check < "$LNBITS_DIR/.app_password"; then
        save_app_password_user_set lnbits
    fi
    set -x
else
    set -e

    if [ ! -s "$LNBITS_DIR/.super_user" ] || [ ! -f "$LNBITS_DIR/database.sqlite3" ]; then
        # The account does not exist until LNbits has run once, so run it here with no published
        # port. LNbits writes .super_user once the account is in the database.
        docker rm -f lnbits-provision > /dev/null 2>&1 || true
        rm -f "$LNBITS_DIR/.super_user"
        docker run --rm -d \
            --name lnbits-provision \
            --volume $LNBITS_DIR/.env:/app/.env \
            --volume $LNBITS_DIR/:/app/data \
            --mount type=bind,src=/mnt/hdd/mynode/lnd/tls.cert,target=/app/tls.cert,readonly \
            --mount type=bind,src=/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon,target=/app/admin.macaroon,readonly \
            --add-host=host.docker.internal:host-gateway \
            lnbits
        for _ in $(seq 1 120); do
            if [ -s "$LNBITS_DIR/.super_user" ] && [ -f "$LNBITS_DIR/database.sqlite3" ]; then
                break
            fi
            sleep 1
        done
        docker stop -t 10 lnbits-provision || true
    fi

    # Rather than start LNbits with its first install page open to the network
    [ -s "$LNBITS_DIR/.super_user" ]
    [ -f "$LNBITS_DIR/database.sqlite3" ]

    set +x
    LNBITS_PASSWORD=$(generate_app_password)
    # "mynode" once this sets the password, "user" if the user completed first install themselves
    PASSWORD_OWNER=$(printf '%s' "$LNBITS_PASSWORD" | docker run "${LNBITS_PASSWORD_ARGS[@]}" set)

    if [ "$PASSWORD_OWNER" = "mynode" ]; then
        save_app_default_password lnbits "$LNBITS_PASSWORD"
    else
        save_app_password_user_set lnbits
    fi
    unset LNBITS_PASSWORD
    set -x
fi
