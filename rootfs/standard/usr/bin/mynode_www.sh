#!/bin/bash

if [ -f /home/bitcoin/.mynode/.www_use_python3 ]; then
    exec /usr/local/bin/python3 /var/www/mynode/mynode.py
else
    exec /usr/bin/python2.7 /var/www/mynode/mynode.py
fi