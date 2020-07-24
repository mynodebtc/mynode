#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

sleep 10s

# Load webpage once to trigger initial load
curl http://localhost/
