#!/bin/bash

# NRestarts counts only systemd's restarts after the UI stopped on its own, not manual restarts. After
# 3 in a boot, alternate with the root Python, so the UI still comes up if it keeps failing on
# MyNode's Python (mynode-python). "systemctl reset-failed www" sets the count back to 0.
restarts=$(systemctl show -p NRestarts --value www.service)
if [ "${restarts:-0}" -ge 3 ] && [ $((${restarts:-0} % 2)) = 1 ]; then
    echo "Restart $restarts this boot, using /usr/local/bin/python3"
    exec /usr/local/bin/python3 /var/www/mynode/mynode.py
fi
exec /usr/bin/mynode-python /var/www/mynode/mynode.py
