#!/bin/bash

set -x

source /usr/share/mynode/mynode_config.sh

# Allow UAS
if [ -f /mnt/hdd/mynode/settings/.uas_usb_enabled ] || [ -f /home/bitcoin/.mynode/.uas_usb_enabled ]; then
    cat /boot/cmdline.txt | grep "usb-storage.quirks="
    if [ $? -eq 0 ]; then
        cat /boot/cmdline.txt | grep "usb-storage.quirks=none"
        if [ $? -eq 0 ]; then
            exit 0
        else
            sed -i "s/usb-storage.quirks=.*/usb-storage.quirks=none/g" /boot/cmdline.txt
            sync
            /usr/bin/mynode-reboot
        fi
    fi
    exit 0
else
    # Disable UAS
    lsusb -t | grep "Driver=uas"
    if [ $? -eq 0 ]; then
        echo "UAS FOUND"
        USBINFO=$(lsusb | grep "SATA 6Gb/s bridge")
        DEVID=$(egrep -o '[0-9a-f]+:[0-9a-f]+' <<< $USBINFO)
        #echo $DEVID

        if [ $IS_RASPI -eq 1 ]; then
            if [ -f /boot/cmdline.txt ]; then
                QUIRK="${DEVID}:u"
                CMDLINE=$(head -n 1 /boot/cmdline.txt)
                cat /boot/cmdline.txt | grep "usb-storage.quirks"
                if [ $? -eq 0 ]; then
                    cat /boot/cmdline.txt | grep "usb-storage.quirks=${QUIRK}"
                    if [ $? -eq 0 ]; then
                        # Quirk already added, exit 0
                        exit 0
                    else
                        # Different quirk exists, update and reboot
                        sed -i "s/usb-storage.quirks=.*/usb-storage.quirks=${QUIRK}/g" /boot/cmdline.txt
                    fi
                else
                    # No quirk found, add it and reboot
                    echo "${CMDLINE} usb-storage.quirks=${QUIRK}" > /boot/cmdline.txt
                fi

                sync
                sleep 5s
                /usr/bin/mynode-reboot
            fi
        fi
    else
        echo "No UAS devices found"
    fi
fi