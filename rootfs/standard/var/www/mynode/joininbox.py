from flask import Blueprint, render_template, redirect, request, flash, send_from_directory
from user_management import check_logged_in
from device_info import read_ui_settings
from systemctl_info import *
import os
import time
import subprocess
import os

mynode_joininbox = Blueprint('mynode_joininbox',__name__)

def get_jm_wallets():
    wallets = []
    wallet_folder = "/mnt/hdd/mynode/joinmarket/wallets/"
    try:
        if os.path.isdir(wallet_folder):
            for f in os.listdir(wallet_folder):
                wallet_path = wallet_folder + f
                if os.path.isfile( wallet_path ):
                    wallet = {}
                    wallet["name"] = f
                    wallets.append(wallet)
    except Exception as e:
        wallets.append({"name": str(e)})
    return wallets

### Page functions
@mynode_joininbox.route("/joininbox")
def joininbox_page():
    check_logged_in()

    # Load page
    templateData = {
        "title": "myNode JoininBox / JoinMarket",
        "wallets": get_jm_wallets(),
        "ui_settings": read_ui_settings(),
    }
    return render_template('joininbox.html', **templateData)


@mynode_joininbox.route("/joininbox/download_wallet", methods=["GET"])
def joininbox_download_wallet():
    check_logged_in()
    wallet_folder = "/mnt/hdd/mynode/joinmarket/wallets/"
    wallet_name = request.args.get('wallet')
    if wallet_name is None:
        flash("Error finding wallet name!", category="error")
        return redirect("/joininbox")

    full_file_path = wallet_folder + wallet_name
    if not os.path.isfile( full_file_path ):
        time.sleep(3)
        flash("Error finding wallet to download!", category="error")
        return redirect("/joininbox")

    return send_from_directory(directory=wallet_folder, filename=wallet_name, as_attachment=True)
