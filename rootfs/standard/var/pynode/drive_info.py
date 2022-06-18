from config import *
from utilities import *
import time
import json
import os
import subprocess
import random
import string
import re


#==================================
# Drive Functions
#==================================
def is_mynode_drive_mounted():
    mounted = True
    try:
        # Command fails and throws exception if not mounted
        output = to_string(subprocess.check_output("grep -qs '/mnt/hdd ext4' /proc/mounts", shell=True))
    except:
        mounted = False
    return mounted

def is_device_mounted(d):
    mounted = True
    try:
        # Command fails and throws exception if not mounted
        ls_output = to_string(subprocess.check_output("grep -qs '/dev/{}' /proc/mounts".format(d), shell=True))
    except:
        mounted = False
    return mounted

def get_drive_size(drive):
    size = -1
    try:
        lsblk_output = to_string(subprocess.check_output("lsblk -b /dev/{} | grep disk".format(drive), shell=True))
        parts = lsblk_output.split()
        size = int(parts[3])
    except:
        pass
    #log_message(f"Drive {drive} size: {size}")
    return size

def get_mynode_drive_size():
    size = -1
    if not is_mynode_drive_mounted():
        return -3
    try:
        size = to_string(subprocess.check_output("df /mnt/hdd | grep /dev | awk '{print $2}'", shell=True)).strip()
        size = int(size) / 1000 / 1000
    except Exception as e:
        size = -2
    return size

def get_data_drive_usage():
    if is_cached("data_drive_usage", 300):
        return get_cached_data("data_drive_usage")
    usage = "0%"
    try:
        if is_mynode_drive_mounted():
            usage = to_string(subprocess.check_output("df -h /mnt/hdd | grep /dev | awk '{print $5}'", shell=True))
            update_cached_data("data_drive_usage", usage)
        else:
            return "N/A"
    except:
        return usage
    return usage
        
def get_os_drive_usage():
    if is_cached("os_drive_usage", 300):
        return get_cached_data("os_drive_usage")
    usage = "0%"
    try:
        usage = to_string(subprocess.check_output("df -h / | grep /dev | awk '{print $5}'", shell=True))
        update_cached_data("os_drive_usage", usage)
    except:
        return usage
    return usage

def check_partition_for_mynode(partition):
    is_mynode = False
    try:
        subprocess.check_output("mount -o ro /dev/{} /mnt/hdd".format(partition), shell=True)
        if os.path.isfile("/mnt/hdd/.mynode"):
            is_mynode = True
    except Exception as e:
        # Mount failed, could be target drive
        pass
    finally:
        time.sleep(1)
        os.system("umount /mnt/hdd")

    return is_mynode

def find_partitions_for_drive(drive):
    partitions = []
    try:
        ls_output = to_string(subprocess.check_output("ls /sys/block/{}/ | grep {}".format(drive, drive), shell=True))
        partitions = ls_output.split()
    except:
        pass
    return partitions

def is_device_detected_by_fdisk(d):
    detected = False
    try:
        # Command fails and throws exception if not mounted
        output = to_string(subprocess.check_output("fdisk -l /dev/{}".format(d), shell=True))
        detected = True
    except:
        pass
    return detected

def find_unmounted_drives():
    drives = []
    try:
        ls_output = subprocess.check_output("ls /sys/block/ | egrep 'hd.*|vd.*|sd.*|nvme.*'", shell=True).decode("utf-8") 
        all_drives = ls_output.split()

        # Only return drives that are not mounted (VM may have /dev/sda as OS drive)
        for d in all_drives:
            if is_device_detected_by_fdisk(d) and not is_device_mounted(d):
                drives.append(d)
    except:
        pass
    return drives


#==================================
# Mount / Unmount Parition Functions
#==================================
def mount_partition(partition, folder_name, permissions="ro"):
    try:
        subprocess.check_output("mkdir -p /mnt/usb_extras/{}".format(folder_name), shell=True)
        subprocess.check_output("mount -o {} /dev/{} /mnt/usb_extras/{}".format(permissions, partition, folder_name), shell=True)
        return True
    except Exception as e:
        return False

def unmount_partition(folder_name):
    os.system("umount /mnt/usb_extras/{}".format(folder_name))
    os.system("rm -rf /mnt/usb_extras/{}".format(folder_name))
    time.sleep(1)


#==================================
# Drive Driver Functions
#==================================
def is_uas_usb_enabled():
    return settings_file_exists("uas_usb_enabled")
