#!/bin/bash

# This will run prior to launching the application

source /usr/share/mynode/mynode_functions.sh

set -x

ALBYHUB_DIR=/mnt/hdd/mynode/albyhub
PENDING_PASSWORD_FILE=$ALBYHUB_DIR/.app_password_pending
PROVISION_CONTAINER=albyhub-provision

# Set up the hub with a generated unlock password, shown on the app page. Alby Hub counts as set
# up once it has started its node, so both steps run here, in a container with no published port.
if has_app_password albyhub; then
    exit 0
fi

set -e

docker rm -f $PROVISION_CONTAINER > /dev/null 2>&1 || true
trap 'docker stop -t 10 $PROVISION_CONTAINER > /dev/null 2>&1 || true' EXIT
docker run --rm -d \
  --name $PROVISION_CONTAINER \
  --add-host=host.docker.internal:host-gateway \
  --volume $ALBYHUB_DIR:/data \
  --mount type=bind,src=/mnt/hdd/mynode/lnd/tls.cert,target=/lnd/tls.cert,readonly \
  --mount type=bind,src=/mnt/hdd/mynode/lnd/albyhub.macaroon,target=/lnd/albyhub.macaroon,readonly \
  --env WORK_DIR="/data" \
  --env LN_BACKEND_TYPE="LND" \
  --env LND_ADDRESS="host.docker.internal:10009" \
  --env LND_CERT_FILE="/lnd/tls.cert" \
  --env LND_MACAROON_FILE="/lnd/albyhub.macaroon" \
  --env ENABLE_ADVANCED_SETUP=false \
  albyhub

ALBYHUB_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $PROVISION_CONTAINER)
ALBYHUB_URL=http://$ALBYHUB_IP:8080

function albyhub_info() {
    curl -sf --max-time 5 $ALBYHUB_URL/api/info | \
        /usr/bin/mynode-python -c 'import json, sys; v = json.load(sys.stdin).get(sys.argv[1]); print("" if v is None else str(v).lower())' "$1"
}

# Prints the HTTP status. 401 means the hub does not accept the password.
function albyhub_post_password() {
    printf '{"unlockPassword": "%s", "permission": "readonly"}' "$2" | \
        curl -s -o /dev/null -w '%{http_code}' --max-time 30 -H 'Content-Type: application/json' --data @- $ALBYHUB_URL$1
}

for _ in $(seq 1 60); do
    if curl -s -o /dev/null --max-time 5 $ALBYHUB_URL/api/info; then
        break
    fi
    sleep 1
done

set +x
if [ "$(albyhub_info setupCompleted)" = "true" ]; then
    # Either an earlier run finished setup but stopped before saving the password, or the user
    # set the hub up themselves
    if [ -s $PENDING_PASSWORD_FILE ] && [ "$(albyhub_post_password /api/unlock "$(cat $PENDING_PASSWORD_FILE)")" != "401" ]; then
        save_app_default_password albyhub "$(cat $PENDING_PASSWORD_FILE)"
    else
        save_app_password_user_set albyhub
    fi
    rm -f $PENDING_PASSWORD_FILE
    exit 0
fi

# Kept until setup completes, so a retry sets up with the same password
if [ ! -s $PENDING_PASSWORD_FILE ]; then
    (umask 077; generate_app_password > $PENDING_PASSWORD_FILE)
fi
ALBYHUB_PASSWORD=$(cat $PENDING_PASSWORD_FILE)

[ "$(albyhub_post_password /api/setup "$ALBYHUB_PASSWORD")" = "204" ]
[ "$(albyhub_post_password /api/start "$ALBYHUB_PASSWORD")" = "200" ]

for _ in $(seq 1 60); do
    if [ "$(albyhub_info setupCompleted)" = "true" ]; then
        break
    fi
    STARTUP_ERROR=$(albyhub_info startupError || true)
    if [ -n "$STARTUP_ERROR" ]; then
        echo "Alby Hub failed to start: $STARTUP_ERROR"
        exit 1
    fi
    sleep 1
done

[ "$(albyhub_info setupCompleted)" = "true" ]
save_app_default_password albyhub "$ALBYHUB_PASSWORD"
rm -f $PENDING_PASSWORD_FILE
unset ALBYHUB_PASSWORD
set -x
