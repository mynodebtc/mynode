from flask import Blueprint, render_template, redirect, request, flash
from user_management import check_logged_in
from device_info import read_ui_settings, get_onion_url_for_service
from application_info import *
from systemctl_info import *
from utilities import *
import os
import time
import subprocess
import os

mynode_joinmarket = Blueprint('mynode_joinmarket',__name__)

def get_jm_wallets():
    wallets = []
    wallet_folder = "/mnt/hdd/mynode/joinmarket/wallets/"
    try:
        if os.path.isdir(wallet_folder):
            for f in os.listdir(wallet_folder):
                wallet_path = wallet_folder + f
                if os.path.isfile( wallet_path ) and not f.startswith("."):
                    wallet = {}
                    wallet["name"] = f
                    wallets.append(wallet)
    except Exception as e:
        wallets.append({"name": str(e)})
    return wallets

def get_joinmarket_version():
    version = "not_found"
    package_info_file = "/home/joinmarket/joinmarket-clientserver/src/joinmarket.egg-info/PKG-INFO"
    try:
        if os.path.isfile(package_info_file):
            with open(package_info_file, 'r') as f:
                lines = f.readlines()
                for l in lines:
                    if "Version: " in l:
                        version = "v" + l.replace("Version: ", "")
        else:
            return "missing_file"
    except:
        version = "exception_error"
    return version

### Page functions
@mynode_joinmarket.route("/joinmarket")
def joininbox_page():
    check_logged_in()

    # Note: the main joinmarket app is actually joininbox
    joinmarket_version = "unknown"
    joininbox_version = "unknown"
    jam_version = "unknown"
    try:
        joinmarket_version = get_joinmarket_version()
        joininbox_version = get_application("joininbox")["current_version"]
        jam_version = get_application("jam")["current_version"]
    except:
        pass

    # Load page
    templateData = {
        "title": "JoinMarket",
        "is_jam_installed": is_installed("jam"),
        "is_jam_enabled": is_service_enabled("jam"),
        "joinmarket_version": joinmarket_version,
        "joininbox_version": joininbox_version,
        "jam_version": jam_version,
        "jam_http_port": 5020,
        "jam_https_port": 5021,
        "jam_tor_address": get_onion_url_for_service("jam"),
        "ob_http_port": 62601,
        "ob_https_port": 62602,
        "ob_tor_address": get_onion_url_for_service("obwatcher"),
        "wallets": get_jm_wallets(),
        "ui_settings": read_ui_settings(),
    }
    return render_template('joinmarket.html', **templateData)


@mynode_joinmarket.route("/joinmarket/download_wallet", methods=["GET"])
def joinmarket_download_wallet():
    check_logged_in()
    wallet_folder = "/mnt/hdd/mynode/joinmarket/wallets/"
    wallet_name = request.args.get('wallet')
    if wallet_name is None:
        flash("Error finding wallet name!", category="error")
        return redirect("/joinmarket")

    full_file_path = wallet_folder + wallet_name
    if not os.path.isfile( full_file_path ):
        time.sleep(3)
        flash("Error finding wallet to download!", category="error")
        return redirect("/joinmarket")

    return download_file(directory=wallet_folder, filename=wallet_name)
