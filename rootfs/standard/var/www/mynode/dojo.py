
from flask import Blueprint, render_template, redirect
from device_info import read_ui_settings, is_installing_docker_images, is_testnet_enabled
from user_management import check_logged_in
from enable_disable_functions import *
from bitcoin_info import get_mynode_block_height
from electrum_info import get_electrs_status, is_electrs_active
from application_info import *
import subprocess
import re
import os

mynode_dojo = Blueprint('mynode_dojo',__name__)

## Status and color
def is_dojo_initialized():
    try:
        dojo_initialized = subprocess.check_output("docker inspect --format={{.State.Running}} db", shell=True)
        dojo_initialized = dojo_initialized.strip()
    except:
        dojo_initialized = ""

    return dojo_initialized == "true"

def get_dojo_status():
    # Find dojo status
    dojo_status = "Disabled"
    dojo_status_color = "gray"

    if is_installing_docker_images():
        dojo_status = "Installing..."
        dojo_status_color = "yellow"
        return dojo_status, dojo_status_color

    if is_testnet_enabled():
        dojo_status = "Requires Mainnet"
        dojo_status_color = "gray"
        return dojo_status, dojo_status_color

    init = is_dojo_initialized()

    if is_service_enabled("dojo"):
        if init:
            if is_electrs_active():
                dojo_status = "Running"
                dojo_status_color = "green"
            else:
                dojo_status = "Waiting on Electrum..."
                dojo_status_color = "yellow"
        else:
            dojo_status = "Issue Starting"
            dojo_status_color = "red"

    return dojo_status, dojo_status_color

def get_dojo_tracker_status():
    try:
        tracker_log = subprocess.check_output("docker logs --tail 100 nodejs", shell=True)
    except:
        return "error"

    lines = tracker_log.splitlines()
    lines.reverse()
    tracker_status = "unknown"

    for line in lines:
        if "Added block header" in line:
            m = re.search("block header ([0-9]+)", line)
            dojo_height = m.group(1)
            bitcoin_height = get_mynode_block_height()
            tracker_status = "Syncing... {} of {}".format(dojo_height, bitcoin_height)
            break
        elif "Finished block" in line:
            m = re.search("Finished block ([0-9]+)", line)
            dojo_height = m.group(1)
            bitcoin_height = get_mynode_block_height()
            tracker_status = "Syncing... {} of {}".format(dojo_height, bitcoin_height)
        elif "Processing active Mempool" in line:
            tracker_status = "Active"
            break
        elif "ER_ACCESS_DENIED_ERROR" in line:
            tracker_status = "MYSQL Connection Error"
            break
    return tracker_status

def get_dojo_version():
    version = "Unknown"
    try:
        version = subprocess.check_output("cat /mnt/hdd/mynode/dojo/docker/my-dojo/.env | grep -i DOJO_VERSION_TAG", shell=True)
        version = version.split("=")[1]
        version = version.strip()
    except:
        version = 'error'
    return version

def get_dojo_admin_key():
    key = 'Not found'
    try:
        key = subprocess.check_output("cat /mnt/hdd/mynode/dojo/docker/my-dojo/conf/docker-node.conf | grep -i NODE_ADMIN_KEY= | cut -c 16-", shell=True)
        key = key.strip()
    except:
        key = 'error'
    return key

def get_dojo_addr():
    addr = 'Not found'
    try:
        addr = subprocess.check_output("docker exec tor cat /var/lib/tor/hsv3dojo/hostname", shell=True)
        page = '/admin'
        addr = addr.strip() + page
    except:
        addr = 'error'
    return addr

### Page functions
@mynode_dojo.route("/dojo")
def dojo_page():
    check_logged_in()

    admin_key = get_dojo_admin_key()
    dojo_v3_addr = get_dojo_addr()

    dojo_status = "Running"
    dojo_status_code = get_service_status_code("dojo")
    if not is_dojo_initialized():
        dojo_status = "Issue Starting"
    elif dojo_status_code != 0:
        dojo_status = "Error"

    # Load page
    templateData = {
        "title": "myNode Dojo",
        "ui_settings": read_ui_settings(),
        "is_dojo_installed": is_dojo_installed(),
        "dojo_status": dojo_status,
        "dojo_version": get_dojo_version(),
        "dojo_enabled": is_service_enabled("dojo"),
        "dojo_tracker_status": get_dojo_tracker_status(),
        "electrs_status": get_electrs_status(),
        "NODE_ADMIN_KEY": admin_key,
        "DOJO_V3_ADDR": dojo_v3_addr
    }
    return render_template('dojo.html', **templateData)

@mynode_dojo.route("/restart-dojo")
def page_restart_dojo():
    check_logged_in()
    restart_service("dojo")
    return redirect("/dojo")
