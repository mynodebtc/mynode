from flask import Blueprint, render_template, redirect
from user_management import check_logged_in
from enable_disable_functions import *
from device_info import *
from application_info import *
from systemctl_info import *
import subprocess
import os


mynode_datum = Blueprint('mynode_datum',__name__)


### Page functions (have prefix /app/<app name/)
@mynode_datum.route("/info")
def datum_page():
    check_logged_in()

    app = get_application("datum")
    app_status = get_application_status("datum")
    app_status_color = get_application_status_color("datum")

    # Load page
    templateData = {
        "title": "myNode - " + app["name"],
        "ui_settings": read_ui_settings(),
        "app_status": app_status,
        "app_status_color": app_status_color,
        "app": app
    }
    return render_template('/app/generic_app.html', **templateData)

