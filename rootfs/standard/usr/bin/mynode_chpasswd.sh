#!/bin/bash

PASSWORD=$1
HASH=$(echo -n "$PASSWORD" | sha256sum | awk '{print $1}')

# Change Linux Password
echo "admin:$PASSWORD" | chpasswd

# Save hashed password
echo "$HASH" > /home/bitcoin/.mynode/.hashedpw

# Change RTL password
sed -i "s/rtlPassHashed=.*/rtlPassHashed=$HASH/g" /opt/mynode/RTL/RTL.conf
systemctl restart rtl