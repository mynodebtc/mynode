#!/bin/bash

if [ -f ./out/file_server_pid ]; then
    PID=$(cat ./out/file_server_pid)
    if ps -p $PID > /dev/null; then
        echo "Stopping HTTP Server ($PID)..."
        kill $PID
        sleep 1
    fi
fi