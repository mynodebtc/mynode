from config import *
import os
import subprocess

# Functions
def get_current_version():
    current_version = "0.0"
    try:
        with open("/usr/share/mynode/version", "r") as f:
            current_version = f.read().strip()
    except:
        current_version = "error"
    return current_version


def update_latest_version():
    os.system("wget "+LATEST_VERSION_URL+" -O /usr/share/mynode/latest_version")
    return True


def get_latest_version():
    latest_version = "0.0"
    try:
        with open("/usr/share/mynode/latest_version", "r") as f:
            latest_version = f.read().strip()
    except:
        latest_version = get_current_version()
    return latest_version


def get_device_serial():
    serial = subprocess.check_output("cat /proc/cpuinfo | grep Serial | cut -d ' ' -f 2", shell=True)
    return serial