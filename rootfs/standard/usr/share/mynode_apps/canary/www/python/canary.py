from flask import Blueprint, render_template
from user_management import check_logged_in
from application_info import get_application, get_application_status, get_application_status_color
from device_info import read_ui_settings
import os
import stat


mynode_canary = Blueprint("mynode_canary", __name__)

CANARY_PASSWORD_FILE = "/mnt/hdd/mynode/canary/admin_password"
MAX_CANARY_PASSWORD_LENGTH = 1024


def get_canary_password():
    password_fd = None
    try:
        password_fd = os.open(CANARY_PASSWORD_FILE, os.O_RDONLY | os.O_NOFOLLOW)
        if not stat.S_ISREG(os.fstat(password_fd).st_mode):
            return ""

        with os.fdopen(password_fd, "r", encoding="ascii") as password_file:
            password_fd = None
            password = password_file.read(MAX_CANARY_PASSWORD_LENGTH + 1).strip()
    except (OSError, UnicodeError):
        return ""
    finally:
        if password_fd is not None:
            os.close(password_fd)

    if len(password) > MAX_CANARY_PASSWORD_LENGTH:
        return ""
    return password


@mynode_canary.route("/info")
def canary_page():
    check_logged_in()

    app = get_application("canary")
    app_status = get_application_status("canary")
    app_status_color = get_application_status_color("canary")

    template_data = {
        "title": "MyNode - " + app["name"],
        "ui_settings": read_ui_settings(),
        "app_status": app_status,
        "app_status_color": app_status_color,
        "app": app,
        "canary_password": get_canary_password(),
    }
    return render_template("/app/canary/canary.html", **template_data)
