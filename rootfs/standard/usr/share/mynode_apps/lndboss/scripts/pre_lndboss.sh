#!/bin/bash

# This will run prior to launching the application

echo "" > /mnt/hdd/mynode/lndboss/auth.json
if [ -f /home/bitcoin/.mynode/.hashedpw_bcrypt ]; then
    HASH_BCRYPT=$(cat /home/bitcoin/.mynode/.hashedpw_bcrypt)
    cat << EOF > /mnt/hdd/mynode/lndboss/auth.json
{
  "username": "admin",
  "passwordHash": "$HASH_BCRYPT"
}
EOF
fi