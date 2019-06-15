#!/bin/bash

# Make sure we have wallet pw
mkdir -p /home/bitcoin/.mynode/
if [ ! -f /home/bitcoin/.mynode/.lndpw ]; then
    < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-24} > /home/bitcoin/.mynode/.lndpw
    chmod 600 /home/bitcoin/.mynode/.lndpw
fi

exit 0