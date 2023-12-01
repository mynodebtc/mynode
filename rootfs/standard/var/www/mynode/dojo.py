
from flask import Blueprint, render_template, redirect
from device_info import read_ui_settings
from user_management import check_logged_in
from enable_disable_functions import *
from electrum_info import get_electrs_status
from dojo_info import *
from application_info import *
from utilities import *
import subprocess
import re
import os

mynode_dojo = Blueprint('mynode_dojo',__name__)


### Page functions
@mynode_dojo.route("/dojo")
def dojo_page():
    check_logged_in()

    admin_key = get_dojo_admin_key()
    dojo_v3_addr = get_dojo_addr()

    dojo_status = get_application_status("dojo")
    tracker_status, tracker_status_text = get_dojo_tracker_status()

    # Load page
    templateData = {
        "title": "Dojo",
        "ui_settings": read_ui_settings(),
        "dojo_status": dojo_status,
        "dojo_version": get_dojo_version(),
        "dojo_enabled": is_service_enabled("dojo"),
        "dojo_tracker_status": tracker_status_text,
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
