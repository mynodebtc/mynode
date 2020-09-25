
from flask import Blueprint, render_template, redirect
from device_info import read_ui_settings
from user_management import check_logged_in
from enable_disable_functions import is_dojo_enabled, enable_dojo, disable_dojo, is_dojo_installed
from bitcoin_info import get_mynode_block_height
from electrum_info import get_electrs_status, is_electrs_active
import subprocess
import re
import os

mynode_dojo = Blueprint('mynode_dojo',__name__)

## Status and color
def get_dojo_status():
    # Find dojo status
    dojo_status = "Disabled"
    dojo_status_color = "gray"
    try:
        dojo_initialized = subprocess.check_output("docker inspect --format={{.State.Running}} db", shell=True)
        dojo_initialized = dojo_initialized.strip()
    except:
        dojo_initialized = ""
    if is_dojo_enabled():
        if dojo_initialized != "false":
            if is_electrs_active():
                dojo_status = "Running"
                dojo_status_color = "green"
            else:
                dojo_status = "Waiting on electrs..."
                dojo_status_color = "yellow"
        else:
            dojo_status = "Issue Starting"
            dojo_status_color = "red"
            dojo_initialized = ""

    return dojo_status, dojo_status_color, dojo_initialized

def get_dojo_tracker_status():
    try:
        tracker_log = subprocess.check_output("/opt/mynode/dojo/docker/my-dojo/dojo.sh logs nodejs | head -n 50", shell=True)
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
        elif "Processing active Mempool" in line:
            tracker_status = "Active"
            break


    return tracker_status


### Page functions
@mynode_dojo.route("/dojo")
def dojo_page():
    check_logged_in()

    NODE_ADMIN_KEY = 'Not found'
    try:
        NODE_ADMIN_KEY = subprocess.check_output("cat /opt/mynode/dojo/docker/my-dojo/conf/docker-node.conf | grep -i NODE_ADMIN_KEY= | cut -c 16-", shell=True)
        NODE_ADMIN_KEY = NODE_ADMIN_KEY.strip()
    except:
        NODE_ADMIN_KEY = 'error'

    DOJO_V3_ADDR = 'Not found'
    try:
        DOJO_V3_ADDR = subprocess.check_output("docker exec tor cat /var/lib/tor/hsv3dojo/hostname", shell=True)
        PAGE = '/admin'
        DOJO_V3_ADDR = DOJO_V3_ADDR.strip() + PAGE
    except:
        DOJO_V3_ADDR = 'error'

    dojo_status, dojo_status_color, dojo_initialized = get_dojo_status()

    # Load page
    templateData = {
        "title": "myNode Dojo",
        "ui_settings": read_ui_settings(),
        "is_dojo_installed": is_dojo_installed(),
        "dojo_status": dojo_status,
        "dojo_status_color": dojo_status_color,
        "dojo_enabled": is_dojo_enabled(),
        "dojo_initialized": dojo_initialized,
        "dojo_tracker_status": get_dojo_tracker_status(),
        "electrs_status": get_electrs_status(),
        "NODE_ADMIN_KEY": NODE_ADMIN_KEY,
        "DOJO_V3_ADDR": DOJO_V3_ADDR
    }
    return render_template('dojo.html', **templateData)

@mynode_dojo.route("/restart-dojo")
def page_toggle_dojo():
    check_logged_in()
    disable_dojo()
    enable_dojo()
    return redirect("/dojo")
