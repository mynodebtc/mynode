
from flask import Blueprint, render_template, redirect, request, url_for
from flask import current_app
from user_management import check_logged_in
from device_info import *
from application_info import *
import subprocess
import re
import os

mynode_generic_app = Blueprint('mynode_generic_app',__name__)

# This is the generic app page handler. Specific ones can override this. 
@mynode_generic_app.route('/app/<name>/info')
def app_generic_info_page(name):
    check_logged_in()

    app = get_application(name)
    if not is_application_valid(name) or app == None:
        flash("Application is invalid", category="error")
        return redirect("/apps")

    app_status = get_application_status(name)

    # Load page
    templateData = {
        "title": "myNode - " + app["name"],
        "ui_settings": read_ui_settings(),
        "app_status": app_status,
        "app": app
    }
    return render_template('/app/generic_app.html', **templateData)
