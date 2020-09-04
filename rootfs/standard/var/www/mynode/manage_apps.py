
from flask import Blueprint, render_template, redirect
from user_management import check_logged_in
from device_info import *
import subprocess
import re
import os

mynode_manage_apps = Blueprint('mynode_manage_apps',__name__)


### Page functions
@mynode_manage_apps.route("/apps")
def caravan_page():
    check_logged_in()

    apps = []
    apps.append({"name":"Bitcoin",              "short_name": "bitcoin"})
    apps.append({"name":"LND",                  "short_name": "lnd"})
    apps.append({"name":"Loop",                 "short_name": "loop"})
    #apps.append({"name":"Electrum Server",      "short_name": "electrs"})
    #apps.append({"name":"LND Hub",              "short_name": "lndhub"})
    #apps.append({"name":"BTC RPC Explorer",     "short_name": "btc_rpc_explorer"})
    apps.append({"name":"Ride the Lightning",   "short_name": "rtl"})
    apps.append({"name":"Thunderhub",           "short_name": "thunderhub"})
    #apps.append({"name":"LNbits",               "short_name": "lnbits"})
    apps.append({"name":"Specter",              "short_name": "specter"})

    for app in apps:
        app["current_version"] = get_app_current_version(app["short_name"])

    # Load page
    templateData = {
        "title": "myNode Manage Apps",
        "ui_settings": read_ui_settings(),
        "apps": apps
    }
    return render_template('manage_apps.html', **templateData)
