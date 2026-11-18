from flask import Blueprint, render_template, redirect, request, flash
from user_management import check_logged_in
from device_info import read_ui_settings, get_usb_extras
from systemctl_info import *
from utilities import is_safe_name
import os
import time
import subprocess

mynode_usb_extras = Blueprint('mynode_usb_extras',__name__)

### Page functions
@mynode_usb_extras.route("/usb_extras/opendime_init")
def usb_extras_opendime_init_page():
    check_logged_in()

    id = request.args.get('id')
    found = False
    devices = get_usb_extras()
    for d in devices:
        if str(d["id"]) == str(id) and int(d["id"]) == int(id) and d["device_type"] == "opendime" and d["state"] == "new":
            if not is_safe_name(d["folder_name"]):
                break
            found = True
            path = "/mnt/usb_extras/" + d["folder_name"] + "/entro.bin"
            subprocess.call(["dd", "if=/dev/urandom", "of="+path, "bs=1024", "count=256"])
            os.system("sync")
            time.sleep(3)
            os.system("systemctl restart usb_extras")
            break

    if found == False:
        flash("Opendime Device Not Found", category="error")
    else:
        flash("Opendime Initialized", category="message")

    return redirect("/")

