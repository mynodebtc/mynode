#!/bin/bash

# This will run prior to launching the application

# Edit app's environment.ts file with current local IP address
LOCAL_IP_ADDR=$(hostname -I | head -n 1 | cut -d' ' -f1)
echo """
export const environment = {
    production: false,
    API_URL: 'http://${LOCAL_IP_ADDR}:3334',
    STRATUM_URL: '${LOCAL_IP_ADDR}:3333'
};
""" > /opt/mynode/publicpoolui/src/environments/environment.ts