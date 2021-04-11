
from flask import Blueprint, render_template, redirect
from user_management import check_logged_in
from device_info import *
from application_info import *
import subprocess
import re
import os

mynode_manage_apps = Blueprint('mynode_manage_apps',__name__)


### Page functions
@mynode_manage_apps.route("/apps")
def manage_apps_page():
    check_logged_in()

    t1 = get_system_time_in_ms()
    apps = get_all_applications(order_by="alphabetic")
    t2 = get_system_time_in_ms()
    # Load page
    templateData = {
        "title": "myNode Manage Apps",
        "ui_settings": read_ui_settings(),
        "load_time": t2-t1,
        "product_key_skipped": skipped_product_key(),
        "apps": apps
    }
    return render_template('manage_apps.html', **templateData)
