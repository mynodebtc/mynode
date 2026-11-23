#!/bin/bash

set -x

# Wait a few second to give marker file a chance to get created
sleep 15s

# Check if 
echo "Checking if docker images have been installed..."
while [ -f /run/mynode/installing_docker_images ]; do
    sleep 30s
done

exit 0