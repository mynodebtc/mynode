#!/bin/bash

set -x

# Wait a few second to give marker file a change to get created
sleep 10s

# Check if 
echo "Checking if docker images have been installed..."
while [ -f /tmp/installing_docker_images ]; do
    sleep 30s
done

exit 0