
from flask import Blueprint, render_template, redirect
from settings import read_ui_settings
from user_management import check_logged_in
from enable_disable_functions import is_dojo_enabled, enable_dojo, disable_dojo
import subprocess
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
            dojo_status = "Running"
            dojo_status_color = "green"
        else:
            dojo_status = "Issue Starting"
            dojo_status_color = "red"
            dojo_initialized = ""
    return dojo_status, dojo_status_color, dojo_initialized

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
        "dojo_status": dojo_status,
        "dojo_status_color": dojo_status_color,
        "dojo_enabled": is_dojo_enabled(),
        "dojo_initialized": dojo_initialized,
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
