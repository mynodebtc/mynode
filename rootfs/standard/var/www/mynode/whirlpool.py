from flask import Blueprint, render_template, redirect
from settings import read_ui_settings
from user_management import check_logged_in
from enable_disable_functions import is_whirlpool_enabled, enable_whirlpool, disable_whirlpool
from device_info import get_service_status_code
import subprocess
import os

mynode_whirlpool = Blueprint('mynode_whirlpool',__name__)

## Status and color
def get_whirlpool_status():
    # Find whirlpool status
    whirlpool_status = "Disabled"
    whirlpool_status_color = "gray"
    whirlpool_initialized = os.path.isfile("/opt/mynode/whirlpool/whirlpool-cli-config.properties")
    if is_whirlpool_enabled():
        get_service_status_code("whirlpool")
        if status != 0:
            whirlpool_status = "Inactive"
            whirlpool_status_color = "red"
        else:
            if whirlpool_initialized:
                whirlpool_status = "Running"
                whirlpool_status_color = "green"
            else:
                whirlpool_status = "Waiting for initialization..."
                whirlpool_status_color = "yellow"
    return whirlpool_status, whirlpool_status_color, whirlpool_initialized

### Page functions
@mynode_whirlpool.route("/whirlpool")
def whirlpool_page():
    check_logged_in()

    whirlpool_api_key = 'Not found'
    try:
        whirlpool_api_key = subprocess.check_output("cat /opt/mynode/whirlpool/whirlpool-cli-config* | grep -i cli.Apikey= | cut -c 12-", shell=True)
    except:
        whirlpool_api_key = 'error'

    whirlpool_status, whirlpool_status_color, whirlpool_initialized = get_whirlpool_status()

    # Load page
    templateData = {
        "title": "myNode Whirlpool",
        "ui_settings": read_ui_settings(),
        "whirlpool_status": whirlpool_status,
        "whirlpool_status_color": whirlpool_status_color,
        "whirlpool_enabled": is_whirlpool_enabled(),
        "whirlpool_initialized": whirlpool_initialized,
        "whirlpool_api_key": whirlpool_api_key
    }
    return render_template('whirlpool.html', **templateData)

@mynode_whirlpool.route("/restart-whirlpool")
def page_toggle_whirlpool():
    check_logged_in()
    os.system("systemctl restart whirlpool --no-pager")
    return redirect("/whirlpool")
