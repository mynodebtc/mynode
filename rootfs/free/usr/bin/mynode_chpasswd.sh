#!/bin/bash

PASSWORD=$1

# Change Linux Password
echo "admin:$PASSWORD" | chpasswd

