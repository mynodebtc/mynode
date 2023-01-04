#!/bin/bash

# This will run prior to launching the application

MY_UID=$(id -u)
MY_GID=$(id -g)

echo "UID=$MY_UID" >  /mnt/hdd/mynode/nostrrsrelay/env
echo "GID=$MY_GID" >> /mnt/hdd/mynode/nostrrsrelay/env