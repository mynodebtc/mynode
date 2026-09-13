#!/bin/bash

PORT="${1:-${MYNODE_FILE_SERVER_PORT:-8000}}"

start_server () {
    echo "Starting HTTP Server on port ${PORT}..."
    cd out || { echo "ERROR: out/ directory not found"; exit 1; }
    python3 -m http.server "$PORT" > /dev/null &
    PID=$!
    cd ../
    echo $PID > ./out/file_server_pid
    sleep 1
}

if [ -f ./out/file_server_pid ]; then
    PID=$(cat ./out/file_server_pid)
    if ps -p $PID > /dev/null; then
        echo "HTTP Server appears to already be running"
    else
        start_server
    fi
else
    start_server
fi