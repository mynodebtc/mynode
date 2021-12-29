#!/usr/bin/python3
import time
import os
import subprocess
import signal
import logging
import random
import string
import json
import atexit
from http.server import HTTPServer, SimpleHTTPRequestHandler
import pyudev
from systemd import journal
from threading import Thread

log = logging.getLogger('mynode')
log.addHandler(journal.JournaldLogHandler())
log.setLevel(logging.INFO)

################################
## USB Device Cache
################################
usb_devices = []

def reset_usb_devices():
    global usb_devices
    for d in usb_devices:
        d.stop()
    usb_devices = []
    write_usb_devices_json()

def add_usb_device(usb_device):
    global usb_devices
    usb_devices.append(usb_device)
    write_usb_devices_json()

def remove_usb_device(usb_device):
    global usb_devices
    new_devices = []
    for d in usb_devices:
        if d.id != usb_device.id:
            new_devices.append(d)
    usb_devices = new_devices
    write_usb_devices_json()

def write_usb_devices_json():
    global usb_devices
    json_str = json.dumps([ob.to_dict() for ob in usb_devices])
    with open('/tmp/usb_extras.json', 'w') as f:
        f.write(json_str)
        f.close()


################################
## Utility Functions
################################

def print_and_log(msg):
    global log
    print(msg)
    log.info(msg)

def set_usb_extras_state(state):
    print_and_log("USB Extras State: {}".format(state))
    try:
        with open("/tmp/.usb_extras_state", "w") as f:
            f.write(state)
        os.system("sync")
        return True
    except:
        return False
    return False

def get_drive_size(drive):
    size = -1
    try:
        lsblk_output = subprocess.check_output(f"lsblk -b /dev/{drive} | grep disk", shell=True).decode("utf-8")
        parts = lsblk_output.split()
        size = int(parts[3])
    except:
        pass
    print_and_log(f"Drive {drive} size: {size}")
    return size

def mount_partition(partition, folder_name, permissions="ro"):
    try:
        subprocess.check_output(f"mkdir -p /mnt/usb_extras/{folder_name}", shell=True)
        subprocess.check_output(f"mount -o {permissions} /dev/{partition} /mnt/usb_extras/{folder_name}", shell=True)
        return True
    except Exception as e:
        return False

def unmount_partition(folder_name):
    os.system(f"umount /mnt/usb_extras/{folder_name}")
    os.system(f"rm -rf /mnt/usb_extras/{folder_name}")
    time.sleep(1)

def find_partitions_for_drive(drive):
    partitions = []
    try:
        ls_output = subprocess.check_output(f"ls /sys/block/{drive}/ | grep {drive}", shell=True).decode("utf-8") 
        partitions = ls_output.split()
    except:
        pass
    return partitions

def is_drive_detected_by_fdisk(d):
    detected = False
    try:
        # Command fails and throws exception if not mounted
        ls_output = subprocess.check_output(f"fdisk -l /dev/{d}", shell=True).decode("utf-8")
        detected = True
    except:
        pass
    return detected

def is_drive_mounted(d):
    mounted = True
    try:
        # Command fails and throws exception if not mounted
        ls_output = subprocess.check_output(f"grep -qs '/dev/{d}' /proc/mounts", shell=True).decode("utf-8") 
    except:
        mounted = False
    return mounted

def find_unmounted_drives():
    drives = []
    try:
        ls_output = subprocess.check_output("ls /sys/block/ | egrep 'hd.*|vd.*|sd.*|nvme.*'", shell=True).decode("utf-8") 
        all_drives = ls_output.split()

        # Only return drives that are not mounted (VM may have /dev/sda as OS drive)
        for d in all_drives:
            if is_drive_detected_by_fdisk(d) and not is_drive_mounted(d):
                drives.append(d)
    except:
        pass
    return drives

################################
## HTTP Server Functions
################################
class NoCacheHTTPRequestHandler(
    SimpleHTTPRequestHandler
):
    def send_response_only(self, code, message=None):
        super().send_response_only(code, message)
        self.send_header('Cache-Control', 'no-store, must-revalidate')
        self.send_header('Expires', '0')

def web_handler_from(directory):
    def _init(self, *args, **kwargs):
        return NoCacheHTTPRequestHandler.__init__(self, *args, directory=self.directory, **kwargs)
    return type(f'HandlerFrom<{directory}>',
                (NoCacheHTTPRequestHandler,),
                {'__init__': _init, 'directory': directory})

################################
## Detection Functions
################################
def check_partition_for_opendime(partition):
    is_opendime = False
    if mount_partition(partition, "temp_check"):
        if os.path.isfile("/mnt/usb_extras/temp_check/support/opendime.png"):
            is_opendime = True
    unmount_partition("temp_check")
    return is_opendime

################################
## Device Handlers
################################
usb_device_id = 0
                
class UsbDeviceHandler:
    def __init__(self):
        global usb_device_id
        self.id = usb_device_id
        usb_device_id = usb_device_id + 1

    def to_dict(self):
        raise NotImplementedError

class OpendimeHandler(UsbDeviceHandler):

    def __init__(self, block_device, partition):
        super().__init__()
        self.device = block_device
        self.device_type = "opendime"
        self.partition = partition
        self.folder_name = f"opendime_{self.id}"
        self.state = "loading_1"
        self.http_server = None
        self.http_server_thread = None

    def to_dict(self):
        dict = {}
        dict["id"] = self.id
        dict["device_type"] = self.device_type
        dict["device"] = self.device
        dict["partition"] = self.partition
        dict["folder_name"] = self.folder_name
        dict["port"] = self.port
        dict["state"] = self.state
        return dict

    def start(self):
        try:
            if mount_partition(self.partition, self.folder_name, "rw"):
                # Check device state
                self.state = "loading_2"
                try:
                    readme_file = f"/mnt/usb_extras/{self.folder_name}/README.txt"
                    private_key_file = f"/mnt/usb_extras/{self.folder_name}/private-key.txt"
                    if os.path.isfile(readme_file):
                        with open(readme_file) as f:
                            content = f.read()
                            if "This Opendime is fresh and unused. It hasn't picked a private key yet." in content:
                                self.state = "new"
                                print_and_log("  Opendime in state 'new'")

                    if os.path.isfile(private_key_file):
                        with open(private_key_file) as f:
                            content = f.read()
                            if "SEALED" in content:
                                self.state = "sealed"
                                print_and_log("  Opendime in state 'sealed'")
                            else:
                                self.state = "unsealed"
                                print_and_log("  Opendime in state 'unsealed'")

                except Exception as e:
                    self.state = "error_reading_opendime"

                self.port = 8010 + (self.id % 10)
                self.http_server = HTTPServer(('', self.port), web_handler_from(f"/mnt/usb_extras/{self.folder_name}"))
                self.http_server_thread = Thread(target = self.http_server.serve_forever)
                self.http_server_thread.setDaemon(True)
                self.http_server_thread.start()
                return True
            else:
                print_and_log("Error mounting partition for opendime")
                return False
        except Exception as e:
            unmount_partition(self.folder_name)
            print_and_log("Opendime Start Exception: {}".format(str(e)))
            return False

    def stop(self):
        try:
            if self.http_server:
                self.http_server.shutdown()
            unmount_partition(self.folder_name)
        except Exception as e:
            print_and_log("Opendime Stop Exception: {}".format(str(e)))

################################
## check_usb_devices()
################################
def check_usb_devices():
    try:
        # if new event, reset state
        # if no new event and in state (mounted), jump to state machine
        
        # Set initial state
        set_usb_extras_state("detecting")
        os.system("umount /mnt/usb_extras")

        # Detect drives
        drives = find_unmounted_drives()
        print_and_log(f"Drives: {drives}")

        # Check exactly one extra drive found
        drive_count = len(drives)
        if drive_count == 0:
            print_and_log("No USB extras found.")
        else:
            set_usb_extras_state("processing")
            for drive in drives:
                # Check drive for partitions
                drive = drives[0]
                partitions = find_partitions_for_drive(drive)
                print_and_log(f"Drive {drive} paritions: {partitions}")

                num_partitions = len(partitions)
                if num_partitions == 0:
                    print_and_log("No partitions found. Nothing to do.")
                elif num_partitions == 1:
                    # Process partition
                    partition = partitions[0]
                    print_and_log("One partition found! Scanning...")
                    if check_partition_for_opendime(partition):
                        print_and_log("Found Opendime!")
                        opendime = OpendimeHandler(drive, partition)
                        if opendime.start():
                            add_usb_device(opendime)
                        else:
                            opendime.stop()
                    else:
                        print_and_log(f"Drive {drive} could not be detected.")
                else:
                    print_and_log(f"{num_partitions} partitions found. Not sure what to do.")

        # Successful scan post init or usb action detected, mark homepage refresh
        os.system("touch /tmp/homepage_needs_refresh")
            
    except Exception as e:
        print_and_log("Exception: {}".format(str(e)))
        set_usb_extras_state("error")
        reset_usb_devices()
        print_and_log("Caught exception. Delaying 30s.")
        time.sleep(30)


################################
## Main
################################
def main():
    # Setup
    os.system("mkdir -p /mnt/usb_extras")

    # Start fresh and check USB devices once on startup 
    unmount_partition("*")
    reset_usb_devices()
    check_usb_devices()

    # Monitor USB and re-check on add/remove
    context = pyudev.Context()
    monitor = pyudev.Monitor.from_netlink(context)
    monitor.filter_by(subsystem='usb')
    # this is module level logger, can be ignored
    print_and_log("Starting to monitor for usb")
    monitor.start()
    print_and_log("Waiting on USB Event...")
    set_usb_extras_state("waiting")
    for device in iter(monitor.poll, None):
        print_and_log("")
        print_and_log("Got USB event: %s", device.action)
        if device.action == 'add':
            check_usb_devices()
        else:
            # HANDLE DEVICE REMOVAL BETTER? This resets all and re-scans
            reset_usb_devices()
            check_usb_devices()
        print_and_log("Waiting on USB Event...")
        set_usb_extras_state("waiting")
    

@atexit.register
def goodbye():
    print_and_log("ATEXIT: Resetting devices")
    unmount_partition("*")
    reset_usb_devices()
    print_and_log("ATEXIT: Done")

# This is the main entry point for the program
if __name__ == "__main__":
    while True:
        try:
            main()
        except Exception as e:
            set_usb_extras_state("error")
            print_and_log("Main Exception: {}".format(str(e)))
            print_and_log("Caught exception. Delaying 30s.")
            unmount_partition("*")
            reset_usb_devices()
            time.sleep(30)
