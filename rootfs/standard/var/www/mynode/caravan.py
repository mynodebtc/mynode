
from flask import Blueprint, render_template, redirect
from settings import read_ui_settings
from user_management import check_logged_in
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
        "ui_settings": read_ui_settings()
    }
    return render_template('caravan.html', **templateData)
