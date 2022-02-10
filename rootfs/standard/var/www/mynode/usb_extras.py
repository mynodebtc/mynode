from flask import Blueprint, render_template, redirect, request, flash
from user_management import check_logged_in
from device_info import read_ui_settings, get_usb_extras
from systemctl_info import *
import os
import time
import subprocess
import os

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
            found = True
            path = "/mnt/usb_extras/" + d["folder_name"] + "/entro.bin"
            os.system("dd if=/dev/urandom of={} bs=1024 count=256".format(path))
            os.system("sync")
            time.sleep(3)
            os.system("systemctl restart usb_extras")
            break

    if found == False:
        flash("Opendime Device Not Found {} {} {}".format(id, devices[0]["id"], devices[0]["device_type"]), category="error")
    else:
        flash("Opendime Initialized", category="message")

    return redirect("/")

