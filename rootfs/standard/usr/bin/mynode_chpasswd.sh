#!/bin/bash

PASSWORD=$1

HASH_SHA256=$(echo -n "$PASSWORD" | sha256sum | awk '{print $1}')
HASH_BCRYPT=$(python3.7 -c "import bcrypt; print(bcrypt.hashpw(b\"$PASSWORD\", bcrypt.gensalt()).decode(\"ascii\"))")

# If pass did not change, exit success
if [ -f /home/bitcoin/.mynode/.hashedpw ]; then
    OLD_HASH_SHA256=$(cat /home/bitcoin/.mynode/.hashedpw)
    if [ "$OLD_HASH_SHA256" = "$HASH_SHA256" ]; then
        exit 0;
    fi
fi


# Change Linux Password
echo "admin:$PASSWORD" | chpasswd

# Save hashed password
echo "$HASH_SHA256" > /home/bitcoin/.mynode/.hashedpw
echo "$HASH_BCRYPT" > /home/bitcoin/.mynode/.hashedpw_bcrypt

# Change RTL password
if [ -f /mnt/hdd/mynode/rtl/RTL-Config.json ]; then
    sed -i "s/\"multiPassHashed\":.*/\"multiPassHashed\": \"$HASH_SHA256\",/g" /mnt/hdd/mynode/rtl/RTL-Config.json
    systemctl restart rtl &
fi

# Change Thunderhub password
if [ -f /mnt/hdd/mynode/thunderhub/thub_config.yaml ]; then
    sed -i "s/masterPassword:.*/masterPassword: 'thunderhub-$HASH_BCRYPT'/g" /mnt/hdd/mynode/thunderhub/thub_config.yaml
    systemctl restart thunderhub &
fi