
from flask import Blueprint, render_template, redirect
from settings import read_ui_settings
from user_management import check_logged_in
from device_info import *
import subprocess
import re
import os

mynode_caravan = Blueprint('mynode_caravan',__name__)


### Page functions
@mynode_caravan.route("/caravan")
def caravan_page():
    check_logged_in()

    # Load page
    templateData = {
        "title": "myNode Caravan",
        "local_ip": get_local_ip(),
        "ui_settings": read_ui_settings()
    }
    return render_template('caravan.html', **templateData)
