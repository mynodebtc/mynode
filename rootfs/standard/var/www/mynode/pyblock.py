from flask import Blueprint, render_template, redirect, request, flash
from user_management import check_logged_in
from device_info import read_ui_settings
from systemctl_info import *
import os
import time
import subprocess
import os

mynode_pyblock = Blueprint('mynode_pyblock',__name__)

### Page functions
@mynode_pyblock.route("/pyblock")
def pyblock_page():
    check_logged_in()

    # Load page
    templateData = {
        "title": "MyNode PyBlock",
        "ui_settings": read_ui_settings(),
    }
    return render_template('pyblock.html', **templateData)

