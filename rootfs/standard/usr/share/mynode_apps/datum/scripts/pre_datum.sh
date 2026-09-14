#!/bin/bash

# This will run prior to launching the application

source /usr/share/mynode/mynode_functions.sh

set -e

# Set the API admin password the first time DATUM starts after an install, which writes a
# fresh config. After that the user may change it in the DATUM config.
DATUM_CONFIG=/mnt/hdd/mynode/datum/datum_config.json
if [ -f $DATUM_CONFIG ] && ! has_app_password datum; then
    DATUM_ADMIN_PASSWORD=$(generate_app_password)
    export DATUM_ADMIN_PASSWORD
    umask 077
    jq '.api.admin_password = env.DATUM_ADMIN_PASSWORD' $DATUM_CONFIG > $DATUM_CONFIG.tmp
    mv $DATUM_CONFIG.tmp $DATUM_CONFIG
    save_app_password datum "$DATUM_ADMIN_PASSWORD"
fi
