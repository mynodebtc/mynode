#!/bin/bash

PASSWORD=$1

HASH_SHA256=$(echo -n "$PASSWORD" | sha256sum | awk '{print $1}')
# Pass the password via the environment so special characters are hashed correctly
HASH_BCRYPT=$(MYNODE_NEW_PASSWORD="$PASSWORD" /usr/local/bin/python3 -c 'import bcrypt, os; print(bcrypt.hashpw(os.environ["MYNODE_NEW_PASSWORD"].encode("utf-8"), bcrypt.gensalt()).decode("ascii"))')

# Never continue with a bad bcrypt hash, or the device would be left with a
# changed login password but stale/empty hash files for the apps
if [ -z "$HASH_BCRYPT" ]; then
    echo "ERROR: Failed to hash password. Password not changed."
    exit 1
fi

# If pass did not change and all hash files exist, exit success
if [ -f /home/bitcoin/.mynode/.hashedpw ]; then
    OLD_HASH_SHA256=$(cat /home/bitcoin/.mynode/.hashedpw)
    if [ "$OLD_HASH_SHA256" = "$HASH_SHA256" ] && [ -f /home/bitcoin/.mynode/.hashedpw_bcrypt ]; then
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
    sed -i "s#masterPassword:.*#masterPassword: \"thunderhub-$HASH_BCRYPT\"#g" /mnt/hdd/mynode/thunderhub/thub_config.yaml
    systemctl restart thunderhub &
fi