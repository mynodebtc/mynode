#!/bin/bash

# Make sure we have wallet pw
mkdir -p /mnt/hdd/mynode/settings
if [ ! -f /mnt/hdd/mynode/settings/.lndpw ]; then
    < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-24} > /mnt/hdd/mynode/settings/.lndpw
    chmod 600 /mnt/hdd/mynode/settings/.lndpw
fi
if [ ! -f /mnt/hdd/mynode/settings/.litpw ]; then
    < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-12} > /mnt/hdd/mynode/settings/.litpw
    chmod 600 /mnt/hdd/mynode/settings/.litpw
fi

exit 0