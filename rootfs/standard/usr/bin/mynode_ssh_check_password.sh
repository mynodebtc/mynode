#!/bin/bash

# Run by pam_exec for SSH password logins, with the password on stdin.
# Refuses the default admin password.

if [ "$PAM_USER" != "admin" ]; then
    exit 0
fi

IFS= read -r -d '' PASSWORD
if [ "$PASSWORD" = "bolt" ]; then
    exit 1
fi
exit 0
