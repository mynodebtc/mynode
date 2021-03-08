from flask import Blueprint, render_template, redirect
from user_management import check_logged_in
from device_info import read_ui_settings
from systemctl_info import *
import subprocess
import os

mynode_joininbox = Blueprint('mynode_joininbox',__name__)


### Page functions
@mynode_joininbox.route("/joininbox")
def joininbox_page():
    check_logged_in()

    # Load page
    templateData = {
        "title": "myNode JoininBox / JoinMarket",
        "ui_settings": read_ui_settings(),
    }
    return render_template('joininbox.html', **templateData)
