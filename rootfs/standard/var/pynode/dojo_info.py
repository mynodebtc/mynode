from enum import Enum
from bitcoin_info import get_mynode_block_height
from utilities import *
import subprocess
import re
import os

class TrackerStatus(Enum):
    ACTIVE = 1
    SYNCING = 2
    ERROR = 3

def is_dojo_initialized():
    try:
        dojo_initialized = to_string(subprocess.check_output("docker inspect --format={{.State.Running}} db", shell=True))
        dojo_initialized = dojo_initialized.strip()
    except:
        dojo_initialized = ""

    return dojo_initialized == "true"

def get_dojo_tracker_status():
    try:
        tracker_log = to_string(subprocess.check_output("docker logs --tail 100 nodejs", shell=True))
    except:
        return TrackerStatus.ERROR, "error"

    lines = tracker_log.splitlines()
    lines.reverse()
    tracker_status_text = "unknown"
    tracker_status = TrackerStatus.ERROR

    for line in lines:
        if "Added block header" in line:
            m = re.search("block header ([0-9]+)", line)
            dojo_height = m.group(1)
            bitcoin_height = get_mynode_block_height()
            tracker_status_text = "Syncing... {} of {}".format(dojo_height, bitcoin_height)
            tracker_status = TrackerStatus.SYNCING
            break
        elif "Finished block" in line:
            m = re.search("Finished block ([0-9]+)", line)
            dojo_height = m.group(1)
            bitcoin_height = get_mynode_block_height()
            tracker_status_text = "Syncing... {} of {}".format(dojo_height, bitcoin_height)
            tracker_status = TrackerStatus.SYNCING
        elif "Processing active Mempool" in line:
            tracker_status_text = "Active"
            tracker_status = TrackerStatus.ACTIVE
            break
        elif "ER_ACCESS_DENIED_ERROR" in line:
            tracker_status_text = "MYSQL Connection Error"
            break
    return tracker_status, tracker_status_text

def get_dojo_version():
    version = "Unknown"
    try:
        version = to_string(subprocess.check_output("cat /mnt/hdd/mynode/dojo/docker/my-dojo/.env | grep -i DOJO_VERSION_TAG", shell=True))
        version = version.split("=")[1]
        version = version.strip()
    except:
        version = 'error'
    return version

def get_dojo_admin_key():
    key = 'Not found'
    try:
        key = to_string(subprocess.check_output("cat /mnt/hdd/mynode/dojo/docker/my-dojo/conf/docker-node.conf | grep -i NODE_ADMIN_KEY= | cut -c 16-", shell=True))
        key = key.strip()
    except:
        key = 'error'
    return key

def get_dojo_addr():
    addr = 'Not found'
    try:
        addr = to_string(subprocess.check_output("docker exec tor cat /var/lib/tor/hsv3dojo/hostname", shell=True))
        page = '/admin'
        addr = addr.strip() + page
    except:
        addr = 'error'
    return addr