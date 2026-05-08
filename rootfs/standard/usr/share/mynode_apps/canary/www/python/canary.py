from flask import Blueprint, render_template
from user_management import check_logged_in
from application_info import get_application, get_application_status, get_application_status_color
from device_info import read_ui_settings
import os


mynode_canary = Blueprint("mynode_canary", __name__)

CANARY_PASSWORD_FILE = "/mnt/hdd/mynode/canary/admin_password"
CANARY_VERSION_FILE = "/mnt/hdd/mynode/settings/canary_version"


def get_canary_password():
    if not os.path.isfile(CANARY_PASSWORD_FILE):
        return ""
    with open(CANARY_PASSWORD_FILE, "r") as password_file:
        return password_file.read().strip()


def get_canary_current_version():
    if not os.path.isfile(CANARY_VERSION_FILE):
        return None
    with open(CANARY_VERSION_FILE, "r") as version_file:
        return version_file.read().strip()[0:16]


@mynode_canary.route("/info")
def canary_page():
    check_logged_in()

    app = get_application("canary")
    current_version = get_canary_current_version()
    if current_version:
        app["current_version"] = current_version

    app_status = get_application_status("canary")
    app_status_color = get_application_status_color("canary")

    template_data = {
        "title": "myNode - " + app["name"],
        "ui_settings": read_ui_settings(),
        "app_status": app_status,
        "app_status_color": app_status_color,
        "app": app,
        "canary_username": "admin@local",
        "canary_password": get_canary_password(),
    }
    return render_template("/app/canary/canary.html", **template_data)
