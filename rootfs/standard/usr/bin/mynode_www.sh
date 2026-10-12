#!/bin/bash

# After a few starts this boot, alternate with the root Python, so the UI still comes up if it
# keeps failing on MyNode's Python (mynode-python)
count=$(journalctl -b -u www.service | grep -c "Started.*MyNode Web Server")
if [ $count -gt 3 ] && [ $(($count % 2)) = 0 ]; then
    echo "Start $count this boot, using /usr/local/bin/python3"
    exec /usr/local/bin/python3 /var/www/mynode/mynode.py
fi
exec /usr/bin/mynode-python /var/www/mynode/mynode.py
