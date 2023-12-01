from flask import Blueprint, render_template, redirect, flash
from user_management import check_logged_in
from device_info import read_ui_settings, reset_sphinxrelay, get_onion_url_sphinxrelay
from utilities import *
from systemctl_info import *
import subprocess
import time
import os

mynode_sphinxrelay = Blueprint('mynode_sphinxrelay',__name__)

### Functions
def get_connection_string():
    s = to_string( get_file_contents("/opt/mynode/sphinxrelay/connection_string.txt") )
    return s


### Page functions
@mynode_sphinxrelay.route("/sphinxrelay")
def sphinxrelay_page():
    check_logged_in()

    sphinxrelay_status = "Error"
    if get_service_status_code("sphinxrelay") == 0:
        sphinxrelay_status = "Running"

    # Load page
    templateData = {
        "title": "MyNode Sphinx Relay",
        "ui_settings": read_ui_settings(),
        "sphinxrelay_status": sphinxrelay_status,
        "sphinxrelay_connection_string": get_connection_string(),
        "sphinxrelay_onion_url": get_onion_url_sphinxrelay(),
    }
    return render_template('sphinxrelay.html', **templateData)

@mynode_sphinxrelay.route("/sphinxrelay/reset")
def sphinxrelay_reset_page():
    check_logged_in()

    reset_sphinxrelay()
    time.sleep(3)

    flash("Sphinx Relay Data Reset", category="message")
    return redirect("/sphinxrelay")