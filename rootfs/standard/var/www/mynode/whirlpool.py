from flask import Blueprint, render_template
from settings import read_ui_settings
from user_management import check_logged_in
from enable_disable_functions import is_whirlpool_enabled, enable_whirlpool, disable_whirlpool
import subprocess
import os

mynode_whirlpool = Blueprint('mynode_whirlpool',__name__)

### Page functions
@mynode_whirlpool.route("/whirlpool")
def whirlpool_page():
    check_logged_in()

    # Find whirlpool status
    whirlpool_initialized = os.path.isfile("/opt/mynode/whirlpool/whirlpool-cli-config.properties")
    whirlpool_status_color = "gray"
    if whirlpool_initialized:
        whirlpool_status = "Initialized."
        if is_whirlpool_enabled():
            status = os.system("systemctl status whirlpool --no-pager")
            if status != 0:
                whirlpool_status_color = "red"
                whirlpool_status = "Initialized but inactive"
            else:
                whirlpool_status_color = "green"
                whirlpool_status = "Running"
    else:
        whirlpool_status = "Not initialized."

    whirlpool_api_key = 'Not found'
    try:
        whirlpool_api_key = subprocess.check_output("cat /opt/mynode/whirlpool/whirlpool-cli-config* | grep -i cli.Apikey= | cut -c 12-", shell=True)
    except:
        whirlpool_api_key = 'error.'

    # Load page
    templateData = {
        "title": "myNode Whirlpool",
        "ui_settings": read_ui_settings(),
        "whirlpool_status_color": whirlpool_status_color,
        "whirlpool_status": whirlpool_status,
        "whirlpool_initialized": whirlpool_initialized,
        "whirlpool_enabled": is_whirlpool_enabled(),
        "whirlpool_api_key": whirlpool_api_key
    }
    return render_template('whirlpool.html', **templateData)