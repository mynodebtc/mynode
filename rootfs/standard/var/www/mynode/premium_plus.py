from flask import Blueprint, render_template, session, abort, Markup, request, redirect, flash
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
from device_info import *
from application_info import *
from user_management import check_logged_in
from enable_disable_functions import restart_service
import json
import time

mynode_premium_plus = Blueprint('mynode_premium_plus',__name__)


### Page functions
@mynode_premium_plus.route("/premium-plus")
def premium_plus_page():
    check_logged_in()

    status = get_premium_plus_token_status()
    status_text = "UNKNOWN"
    if get_premium_plus_is_connected():
        status_text = "Connected!"
    else:
        if has_premium_plus_token():
            status_text = "Not Connected ({})".format(status)
        else:
            status_text = "Please Configure an Access Token"

    
    # Load page
    templateData = {
        "title": "myNode Premium+",
        "has_access_token": has_premium_plus_token(),
        "access_token": get_premium_plus_token(),
        "premium_plus_settings": get_premium_plus_settings(),
        "status": status,
        "status_text": status_text,
        "is_connected": get_premium_plus_is_connected(),
        "last_sync": get_premium_plus_last_sync(),
        "ui_settings": read_ui_settings()
    }
    return render_template('premium_plus.html', **templateData)

@mynode_premium_plus.route("/premium-plus/sync")
def premium_plus_sync_page():
    check_logged_in()

    update_application_json_cache()
    restart_service("premium_plus_connect")
    restart_service("lnd_backup")

    time.sleep(8)
    flash("Syncing...", category="message")
    return redirect("/premium-plus")

@mynode_premium_plus.route("/premium-plus/clear-token")
def premium_plus_clear_token_page():
    check_logged_in()
    delete_premium_plus_token()
    reset_premium_plus_token_status()

    restart_service("premium_plus_connect")

    time.sleep(5)
    flash("Token Cleared", category="message")
    return redirect("/premium-plus")

@mynode_premium_plus.route("/premium-plus/set-token", methods=["POST"])
def premium_plus_set_token_page():
    check_logged_in()
    token = request.form.get('token')
    if token == None:
        flash("Missing Token", category="error")
        return redirect("/premium-plus")
    save_premium_plus_token(token)

    restart_service("premium_plus_connect")
    restart_service("lnd_backup")

    time.sleep(5)
    flash("Token Set", category="message")
    return redirect("/premium-plus")

@mynode_premium_plus.route("/premium-plus/toggle-setting")
def premium_plus_toggle_setting_page():
    check_logged_in()
    name = request.args.get('name')
    enabled = request.args.get('enabled')
    if name == None or enabled == None:
        flash("Missing Parameter", category="error")
        return redirect("/premium-plus")

    # Save value
    premium_plus_setting_names = get_premium_plus_setting_names()
    if   (name in premium_plus_setting_names):
        if (enabled == "1"):
            create_settings_file(name)
        else:
            delete_settings_file(name)
    else:
        flash("Unknown Setting", category="error")
        return redirect("/premium-plus")
    
    restart_service("premium_plus_connect")
    restart_service("lnd_backup")

    time.sleep(5)
    flash("Setting Updated!", category="message")
    return redirect("/premium-plus")