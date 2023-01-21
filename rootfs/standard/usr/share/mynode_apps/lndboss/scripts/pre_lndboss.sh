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

mkdir -p /mnt/hdd/mynode/lndboss/local
cat << EOF > /mnt/hdd/mynode/lndboss/config.json
{
  "default_saved_node": "local"
}
EOF
cat << EOF > /mnt/hdd/mynode/lndboss/local/credentials.json
{
  "cert_path": "/.lnd/tls.cert",
  "macaroon_path": "/.lnd/data/chain/bitcoin/mainnet/admin.macaroon",
  "socket": "host.docker.internal:10009"
}
EOF


# Create env file
MY_UID=$(id -u)
MY_GID=$(id -g)
echo "UID=$MY_UID" >  /mnt/hdd/mynode/lndboss/env
echo "GID=$MY_GID" >> /mnt/hdd/mynode/lndboss/env