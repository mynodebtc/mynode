#!/bin/bash

set -e
set -x

while true; do
    # Rotate logs
    logrotate /etc/logrotate.conf
    
    # Check for any "lost" logs that are growing too large
    LARGE_FILE_COUNT=$(find /var/log/ -type f -size +10M | wc -l)
    if [ "$LARGE_FILE_COUNT" -gt "0" ]; then
        # Delete the files and restart syslog
        find /var/log/ -type f -size +10M | sudo xargs rm -f
        systemctl restart syslog
    fi

    # Sleep
    sleep 10m
done

# We should not exit
exit 1
