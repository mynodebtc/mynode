from flask import Blueprint, render_template
from user_management import check_logged_in
from enable_disable_functions import *
from device_info import *
from application_info import *
from systemctl_info import *


mynode_tunnelsats = Blueprint('mynode_tunnelsats', __name__)


@mynode_tunnelsats.route("/info")
def tunnelsats_page():
    check_logged_in()

    app = get_application("tunnelsats")
    app_status = get_application_status("tunnelsats")
    app_status_color = get_application_status_color("tunnelsats")

    templateData = {
        "title": "MyNode - " + app["name"],
        "ui_settings": read_ui_settings(),
        "app_status": app_status,
        "app_status_color": app_status_color,
        "app": app
    }
    return render_template('/app/generic_app.html', **templateData)
