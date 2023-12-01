#!/bin/bash

if [ -f /home/bitcoin/.mynode/.www_use_python3 ]; then
    exec /usr/local/bin/python3 /var/www/mynode/mynode.py
else
    # If not forcing python3, use prefer python3 unless in restart cycle
    count=$(journalctl -b -u www.service | grep -c "Started MyNode Web Server")
    modcount=$(($count % 5))
    if [ "$modcount" -eq 4 ]; then
        echo "RESTART COUNT: $modcount (PYTHON2)"
        exec /usr/bin/python2.7 /var/www/mynode/mynode.py
    else
        echo "RESTART COUNT: $modcount (PYTHON3)"
        exec /usr/local/bin/python3 /var/www/mynode/mynode.py
    fi
fi