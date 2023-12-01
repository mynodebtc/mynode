from flask import Blueprint, render_template, redirect
from user_management import check_logged_in
from enable_disable_functions import *
from device_info import read_ui_settings, is_testnet_enabled, get_local_ip, get_onion_url_for_service
from application_info import *
from systemctl_info import *
import subprocess
import os

mynode_whirlpool = Blueprint('mynode_whirlpool',__name__)

## Status and color
def is_whirlpool_initialized():
    return os.path.isfile("/mnt/hdd/mynode/whirlpool/whirlpool-cli-config.properties")


### Page functions
@mynode_whirlpool.route("/whirlpool")
def whirlpool_page():
    check_logged_in()

    whirlpool_api_key = 'Not found'
    try:
        whirlpool_api_key = to_string(subprocess.check_output("cat /mnt/hdd/mynode/whirlpool/whirlpool-cli-config* | grep -i cli.Apikey= | cut -c 12-", shell=True))
    except:
        whirlpool_api_key = 'error'

    whirlpool_status = "Running"
    whirlpool_status_code = get_service_status_code("whirlpool")
    if not is_whirlpool_initialized():
        whirlpool_status = "Waiting on Initialization..."
    elif whirlpool_status_code != 0:
        whirlpool_status = "Inactive"

    # Load page
    templateData = {
        "title": "MyNode Whirlpool",
        "ui_settings": read_ui_settings(),
        "local_ip": get_local_ip(),
        "whirlpool_onion_url": get_onion_url_for_service("whirlpool"),
        "whirlpool_status": whirlpool_status,
        "whirlpool_enabled": is_service_enabled("whirlpool"),
        "whirlpool_initialized": is_whirlpool_initialized(),
        "whirlpool_api_key": whirlpool_api_key
    }
    return render_template('whirlpool.html', **templateData)

@mynode_whirlpool.route("/restart-whirlpool")
def page_toggle_whirlpool():
    check_logged_in()
    os.system("systemctl restart whirlpool --no-pager")
    return redirect("/whirlpool")

@mynode_whirlpool.route("/reset-whirlpool")
def page_reset_whirlpool():
    check_logged_in()
    os.system("rm -f /opt/mynode/whirlpool/whirlpool-cli-config.properties")
    os.system("rm -f /mnt/hdd/mynode/whirlpool/whirlpool-cli-config.properties")
    os.system("systemctl restart whirlpool --no-pager")
    return redirect("/whirlpool")
