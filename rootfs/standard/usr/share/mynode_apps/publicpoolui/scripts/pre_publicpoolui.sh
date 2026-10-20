#!/bin/bash

# This will run prior to launching the application

# Edit app's environment.ts file with current local IP address. The API is reached through
# nginx at /api on the UI's own port, so it works over HTTP, HTTPS and Tor.
LOCAL_IP_ADDR=$(hostname -I | head -n 1 | cut -d' ' -f1)
echo """
export const environment = {
    production: false,
    API_URL: '',
    STRATUM_URL: '${LOCAL_IP_ADDR}:3333'
};
""" > /opt/mynode/publicpoolui/src/environments/environment.ts