#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

sleep 60s

# should this long code be splitted to own .sh file?
# handle /first_install if needed
#
# Step 1: Retrieve super_user ID and remove quotes
export SUPER_USER_ID=$(sudo sqlite3 /mnt/hdd/mynode/lnbits/database.sqlite3 \
    "SELECT value FROM system_settings WHERE id='super_user';" | sed 's/\"//g')

# Step 2: Check if first_install is done for the specific super_user ID
export FIRST_INSTALL_STATUS=$(sudo sqlite3 /mnt/hdd/mynode/lnbits/database.sqlite3 \
    "SELECT COUNT(*) FROM accounts WHERE id = '$SUPER_USER_ID' \
    AND username IS NOT NULL;")

if [[ $FIRST_INSTALL_STATUS -eq 1 ]]; then
    echo "FIRST_INSTALL done. Get admin details from Settings page."
else
    echo "FIRST_INSTALL not completed. Doing now..."

    # Step 3: Make the first_install API call
    curl -v -X PUT https://127.0.0.1:5001/api/v1/auth/first_install \
        -H "Content-Type: application/json" \
        -d '{
            "username": "admin",
            "password": "securebolt",
            "password_repeat": "securebolt"
        }' \
        -k

    # Step 4: Update accounts table with correct username and password_hash ("bolt")
    sudo sqlite3 /mnt/hdd/mynode/lnbits/database.sqlite3 \
        "UPDATE accounts SET username = 'admin', \
        password_hash = '\$2b\$12\$GWNtn8GarOLpc5XKMcqFMuY05vIIKWkLtbPSjvqho0P2CLaiNCHHm' \
        WHERE id = '$SUPER_USER_ID';"

    # remove username and password sql here for debugging
    # sudo sqlite3 /mnt/hdd/mynode/lnbits/database.sqlite3 \
    #     "UPDATE accounts SET username = NULL, \
    #     password_hash = NULL \
    #     WHERE id = '$SUPER_USER_ID';"

fi
