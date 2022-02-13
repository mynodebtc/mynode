#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

if [ -f /opt/mynode/corsproxy/node_modules/hapi/lib/defaults.js ]; then
    sed -i "s/tmpDir/tmpdir/g" /opt/mynode/corsproxy/node_modules/hapi/lib/defaults.js
fi