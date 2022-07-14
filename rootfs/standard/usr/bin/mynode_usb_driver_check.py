#!/usr/local/bin/python3

import os
import re
import logging
import argparse
from systemd import journal
from utilities import *
from device_info import *

args = None
def get_args():
    global args
    return args
def set_args(a):
    global args
    args = a

def is_uas_forced():
    if os.path.isfile("/home/bitcoin/.mynode/uas_usb_enabled") or \
       os.path.isfile("/mnt/hdd/mynode/settings/uas_usb_enabled"):
        return True
    return False

def device_checks_uas():
    d = get_device_type()
    if (d == "raspi4" or d == "rockpi4"):
        return True
    return False

def has_quirks_setting():
    d = get_device_type()
    if d == "raspi4":
        line = run_linux_cmd("head -n 1 /boot/cmdline.txt")
        if "usb-storage.quirks=" in line:
            return True
    elif d == "rockpi4":
        lines = run_linux_cmd("cat /boot/armbianEnv.txt")
        if "usbstoragequirks=" in lines:
            return True
    else:
        raise Exception("Unexpected Device Type")
    return False

def get_current_usb_quirks():
    d = get_device_type()
    quirks = []
    try:
        if d == "raspi4":
            if os.path.isfile("/boot/cmdline.txt"):
                content = run_linux_cmd("head -n 1 /boot/cmdline.txt")
                m = re.search("usb-storage.quirks=(.+)", content)
                quirks_string = m.group(1)
                quirks = quirks_string.split(",")
            else:
                raise Exception("Missing file: /boot/cmdline.txt")
        elif d == "rockpi4":
            if os.path.isfile("/boot/armbianEnv.txt"):
                content = run_linux_cmd("cat /boot/armbianEnv.txt")
                m = re.search("usbstoragequirks=(.+)", content)
                quirks_string = m.group(1)
                quirks = quirks_string.split(",")
            else:
                raise Exception("Missing file: /boot/armbianEnv.txt")
        else:
            raise Exception("Unexpected Device Type")
    except Exception as e:
        log_message("Exception in get_current_usb_quirks: {}".format(str(e)))
    return quirks

def generate_quirks_string(quirks_list):
    quirks_string = ""
    d = get_device_type()
    if d == "raspi4":
        quirks_string += "usb-storage.quirks="
    elif d == "rockpi4":
        quirks_string += "usbstoragequirks="
    else:
        raise Exception("Unexpected Device Type")

    for q in quirks_list:
        quirks_string += q + ","
    quirks_string = quirks_string.rstrip(",")
    return quirks_string

def update_usb_quirks(quirks_list):
    d = get_device_type()
    quirks_string = generate_quirks_string(quirks_list)
    log_message("Updating Quirks: {}".format(quirks_string))
    if has_quirks_setting():
        # Update Quirks
        if d == "raspi4":
            run_linux_cmd("sed -i \"s/usb-storage.quirks=.*/"+quirks_string+"/g\" /boot/cmdline.txt")
        elif d == "rockpi4":
            run_linux_cmd("sed -i \"s/usbstoragequirks=.*/"+quirks_string+"/g\" /boot/armbianEnv.txt")
            run_linux_cmd("mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr")
        else:
            raise Exception("Unexpected Device Type")
    else:
        # Add Quirks
        if d == "raspi4":
            contents = run_linux_cmd("head -n 1 /boot/cmdline.txt").strip()
            contents += " " + quirks_string
            set_file_contents("/boot/cmdline.txt", contents)
        elif d == "rockpi4":
            # Rock pi 4 normally never has this missing, if so, need updates
            run_linux_cmd("sed -i \"s/usbstoragequirks=.*/"+quirks_string+"/g\" /boot/armbianEnv.txt")
            run_linux_cmd("mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr")
        else:
            raise Exception("Unexpected Device Type")

def remove_usb_quirks():
    if has_quirks_setting():
        current = get_current_usb_quirks()
        if current != ["none"]:
            update_usb_quirks(["none"])
            reboot()
    else:
        # No quirks setting, nothing to do
        return

def get_quirks_from_uas_devices():
    quirks = []
    lsusbt_output = run_linux_cmd("lsusb -t")
    if "Driver=uas" in lsusbt_output:
        log_message("UAS Driver in use! Looking for likely candidates...")
        lsusb_output = run_linux_cmd("lsusb")
        lsusb_lines = lsusb_output.splitlines()
        for line in lsusb_lines:
            try:
                if "SATA 6Gb/s bridge" in line:
                    m = re.search("Bus ([0-9]+) Device ([0-9]+): ID (\S+)", line)
                    bus = m.group(1)
                    dev = m.group(2)
                    id = m.group(3)
                    quirks.append(id+":u")
            except Exception as e:
                log_message("Unable to scan USB device: {} ({})".format(line, e))
    return quirks

def get_required_usb_quirks():
    required_quirks = []

    # Add known devices
    required_quirks.append("174c:55aa:u") # ASMedia Technology Inc.
    required_quirks.append("152d:1561:u") # JMicron Technology Corp.
    required_quirks.append("152d:0578:u") # JMicron Technology Corp.

    # Add any devices currently found as UAS
    required_quirks += get_quirks_from_uas_devices()

    # Remove duplicates
    required_quirks = list(set(required_quirks))

    return required_quirks

def reboot():
    if not get_args().no_reboot:
        log_message("Rebooting...")
        run_linux_cmd("sync")
        time.sleep(3)
        run_linux_cmd("mynode-reboot")
    else:
        log_message("Skipping reboot.")

def main():
    parser = argparse.ArgumentParser(description='Check and Update USB Drivers')
    #parser.add_argument('--no-modify', action='store_true', help="Do not modify any files")
    parser.add_argument('--no-reboot', action='store_true', help="Do not reboot the device after updating files")
    args = parser.parse_args()
    set_args(args)

    if not device_checks_uas():
        log_message("Device doesn't need to check UAS. Exiting.")
        return

    if is_uas_forced():
        log_message("UAS is allowed by settings. Removing USB quirks.")
        remove_usb_quirks()
        return

    current_quirks = get_current_usb_quirks()
    print("Current Quirks:  {}".format(current_quirks))
    required_quirks = get_required_usb_quirks()
    print("Required Quirks: {}".format(required_quirks))
    updated_quirks = current_quirks.copy()
    for r in required_quirks:
        if r not in current_quirks:
            updated_quirks.append(r)

    if updated_quirks != current_quirks:
        update_usb_quirks(updated_quirks)
        reboot()
    else:
        log_message("No update necessary. Exiting.")


# This is the main entry point for the program
if __name__ == "__main__":
    try:
        log = logging.getLogger('usb_driver_check')
        log.addHandler(journal.JournaldLogHandler())
        log.setLevel(logging.INFO)
        set_logger(log)

        main()
    except Exception as e:
        log_message("Exception: {}".format(str(e)))