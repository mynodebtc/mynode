#!/bin/bash

# Set the admin password (web UI and SSH). The new password is read from stdin.
IFS= read -r PASSWORD

if [ -z "$PASSWORD" ]; then
    echo "ERROR: No password given. Password not changed."
    exit 1
fi

# Change Linux Password
echo "admin:$PASSWORD" | chpasswd
