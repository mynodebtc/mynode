from flask import Blueprint, render_template
from user_management import check_logged_in
from application_info import get_application, get_application_status, get_application_status_color
from device_info import read_ui_settings


mynode_canary = Blueprint("mynode_canary", __name__)


@mynode_canary.route("/info")
def canary_page():
    check_logged_in()

    app = get_application("canary")
    app_status = get_application_status("canary")
    app_status_color = get_application_status_color("canary")

    template_data = {
        "title": "myNode - " + app["name"],
        "ui_settings": read_ui_settings(),
        "app_status": app_status,
        "app_status_color": app_status_color,
        "app": app,
    }
    return render_template("/app/generic_app.html", **template_data)
