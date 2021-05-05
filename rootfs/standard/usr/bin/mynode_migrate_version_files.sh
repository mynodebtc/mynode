#!/bin/bash

# Migrate from version file to version+install combo
# Check install for sd storage
FILES=$(ls /home/bitcoin/.mynode/*_version)
for file in $FILES; do 
    filename=$(basename $file)
    shortname=${filename::-8}
    touch /home/bitcoin/.mynode/install_$shortname
done
# Check install for ssd storage
FILES=$(ls /mnt/hdd/mynode/settings/*_version)
for file in $FILES; do 
    filename=$(basename $file)
    shortname=${filename::-8}
    touch /mnt/hdd/mynode/settings/install_$shortname
done
sync