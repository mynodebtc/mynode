
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
    app_status_color = get_application_status_color(name)
    app_password = get_application_password(name)

    # BTCPay's administrator is whichever account holds its ServerAdmin role, which may be one the
    # user registered before MyNode could claim one. Ask BTCPay, so the page never shows a login
    # name the node only assumed.
    login_username_live = False
    if name == "btcpayserver":
        admins = get_btcpay_admins()
        if admins:
            app["login_username"] = ", ".join(admins)
            login_username_live = True

    # Load page
    templateData = {
        "title": app["name"],
        "ui_settings": read_ui_settings(),
        "app_status": app_status,
        "app_status_color": app_status_color,
        "app_password": app_password,
        # The username in the app JSON is the one MyNode set. Once the login is the user's own,
        # that no longer describes the account, so the page stops showing it - unless it was read
        # from the app itself, in which case it is the real one either way.
        "app_password_user_set": app_password == APP_PASSWORD_USER_SET,
        "login_username_live": login_username_live,
        "app": app
    }
    return render_template('/app/generic_app.html', **templateData)
