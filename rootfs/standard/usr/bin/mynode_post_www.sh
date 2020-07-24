#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

sleep 2s

# Load webpage once to trigger initial load - some setup is not triggered until first page load
curl http://localhost/ || \
    ( sleep 5s && curl http://localhost/ ) || \
    ( sleep 5s && curl http://localhost/ ) || \
    ( sleep 5s && curl http://localhost/ ) || \
    ( sleep 5s && curl http://localhost/ ) 
