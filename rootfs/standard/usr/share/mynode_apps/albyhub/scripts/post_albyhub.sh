#!/bin/bash

# This will run after launching the application

source /usr/share/mynode/mynode_functions.sh

ALBYHUB_DIR=/mnt/hdd/mynode/albyhub

if ! has_app_password albyhub || is_app_password_user_set albyhub; then
    exit 0
fi

# Stop showing the saved password once the hub no longer accepts it, which means the user
# changed it in Alby Hub itself
function check_saved_password() {
    for _ in $(seq 1 600); do
        if curl -s -o /dev/null --max-time 5 http://127.0.0.1:3040/api/info; then
            break
        fi
        sleep 1
    done

    STATUS=$(printf '{"unlockPassword": "%s", "permission": "readonly"}' "$(cat $ALBYHUB_DIR/.app_password)" | \
        curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H 'Content-Type: application/json' --data @- http://127.0.0.1:3040/api/unlock)
    if [ "$STATUS" = "401" ]; then
        save_app_password_user_set albyhub
    fi
}

# Alby Hub can take minutes to answer on a busy node, longer than the service's start timeout,
# so the check runs in the background
check_saved_password > /dev/null 2>&1 &

exit 0
