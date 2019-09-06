#!/bin/bash

start_server () {
    echo "Starting HTTP Server on port 8000..."
    cd out
    python3 -m http.server > /dev/null &
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