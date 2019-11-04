#!/bin/bash

# Generate LND Config
cp /usr/share/mynode/lnd.conf /mnt/hdd/mynode/lnd/lnd.conf
touch /mnt/hdd/mynode/settings/lnd_additional_config
echo "" >> /mnt/hdd/mynode/lnd/lnd.conf
echo "" >> /mnt/hdd/mynode/lnd/lnd.conf
echo "### CUSTOM LND CONFIG ###" >> /mnt/hdd/mynode/lnd/lnd.conf
echo "" >> /mnt/hdd/mynode/lnd/lnd.conf
cat /mnt/hdd/mynode/settings/lnd_additional_config >> /mnt/hdd/mynode/lnd/lnd.conf

ALIAS=$(cat /mnt/hdd/mynode/settings/.lndalias)
sed -i "s/alias=.*/alias=$ALIAS/g" /mnt/hdd/mynode/lnd/lnd.conf
chown bitcoin:bitcoin /mnt/hdd/mynode/lnd/lnd.conf