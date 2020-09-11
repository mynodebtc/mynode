#!/bin/bash

set -e
set -x 

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_app_versions.sh

# NOTE: Background services will run before mynode service completes, so a drive MAY NOT be attached

COUNTER=0

while true; do

    # Check for under voltage, throttling, etc... every 2 min on Raspis
    if [ $(( $COUNTER % 2 )) -eq 0 ]; then
        if [ $IS_RASPI -eq 1 ]; then
            STATUS=$(vcgencmd get_throttled)
            STATUS=${STATUS#*=}
            echo $STATUS > /tmp/get_throttled_data
        fi
    fi


    # Increment counter and sleep 1 min
    COUNTER=$((COUNTER+1))
    sleep 1m
done
