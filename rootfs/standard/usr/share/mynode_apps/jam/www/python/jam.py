from flask import Blueprint, render_template, redirect
from user_management import check_logged_in
from enable_disable_functions import *
from device_info import *
from application_info import *
from systemctl_info import *
import subprocess
import os


mynode_jam = Blueprint('mynode_jam',__name__)


### Page functions (have prefix /app/<app name/)
@mynode_jam.route("/info")
def jam_page():
    check_logged_in()

    app = get_application("jam")
    app_status = get_application_status("jam")
    app_status_color = get_application_status_color("jam")

    # Load page
    templateData = {
        "title": "MyNode - " + app["name"],
        "ui_settings": read_ui_settings(),
        "app_status": app_status,
        "app_status_color": app_status_color,
        "app": app
    }
    return render_template('/app/generic_app.html', **templateData)

