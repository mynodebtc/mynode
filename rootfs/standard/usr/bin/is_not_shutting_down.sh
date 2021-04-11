#!/bin/bash

# Wait to see if bitcoin is synced
echo "Checking if device is shutting down..."
if [ ! -f "/tmp/shutting_down" ]; then
    echo "Not shutting down!"
    exit 0
fi

echo "Device is shutting down... delay and exit failure"
sleep 30s
exit 1