from flask import Blueprint, render_template, redirect, request, flash
from user_management import check_logged_in
from device_info import read_ui_settings
from systemctl_info import *
import os
import time
import subprocess
import os

mynode_bos = Blueprint('mynode_bos',__name__)

### Page functions
@mynode_bos.route("/bos")
def bos_page():
    check_logged_in()

    # Load page
    templateData = {
        "title": "myNode Balance of Satoshis",
        "ui_settings": read_ui_settings(),
    }
    return render_template('bos.html', **templateData)

