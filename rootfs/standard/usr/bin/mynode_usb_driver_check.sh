#!/bin/bash

set -x

source /usr/share/mynode/mynode_config.sh

lsusb -t | grep "Driver=uas"
if [ $? -eq 0 ]; then
    echo "UAS FOUND"
    read PORT DEV <<< $(lsusb -t | grep 'Driver=uas' | head -n 1 | awk '{ print $3,$5 }')
    PORT=$(egrep -o '[0-2]+' <<< $PORT)
    DEV=$(egrep -o '[0-2]+' <<< $DEV)

    USBINFO=$(lsusb -s $PORT:$DEV)
    DEVID=$(egrep -o '[0-9a-f]+:[0-9a-f]+' <<< $USBINFO)
    #echo $DEVID

    if [ $IS_RASPI -eq 1 ]; then
        QUIRK="${DEVID}:u"
        CMDLINE=$(head -n 1 /boot/cmdline.txt)
        cat /boot/cmdline.txt | grep "usb-storage.quirks"
        if [ $? -eq 0 ]; then
            sed -i "s/usb-storage.quirks=.*/usb-storage.quirks=${QUIRK}/g" /boot/cmdline.txt
            sync
            exit 0
        else
            echo "${CMDLINE} usb-storage.quirks=${QUIRK}" > /boot/cmdline.txt
        fi

        sync
        sleep 5s
        reboot
    fi
else
    echo "No UAS devices found"
fi
