
from flask import Blueprint, render_template, redirect, request
from user_management import check_logged_in
from device_info import *
from application_info import *
import subprocess
import re
import os

mynode_marketplace = Blueprint('mynode_marketplace',__name__)


### Page functions
@mynode_marketplace.route("/marketplace")
def marketplace_page():
    check_logged_in()

    t1 = get_system_time_in_ms()
    apps = get_all_applications(order_by="alphabetic")
    t2 = get_system_time_in_ms()

    categories = [{"name": "bitcoin_app", "title": "Bitcoin Apps"},
                  {"name": "lightning_app", "title": "Lightning Apps"},
                  {"name": "uncategorized", "title": "Uncategorized"}
                ]

    # Load page
    templateData = {
        "title": "myNode Marketplace",
        "ui_settings": read_ui_settings(),
        "load_time": t2-t1,
        "product_key_skipped": skipped_product_key(),
        "categories": categories,
        "apps": apps,
        "has_customized_app_versions": has_customized_app_versions(),
    }
    return render_template('marketplace.html', **templateData)

@mynode_marketplace.route("/marketplace/<app_name>")
def marketplace_app_page(app_name):
    check_logged_in()

    app = get_application(app_name)
    if not is_application_valid(app_name) or app == None:
        flash("Application is invalid", category="error")
        return redirect("/marketplace")

    app_status = get_application_status(app_name)

    # Load page
    templateData = {
        "title": "myNode - " + app["name"],
        "ui_settings": read_ui_settings(),
        "product_key_skipped": skipped_product_key(),
        "app_status": app_status,
        "app": app
    }
    return render_template('/marketplace_app.html', **templateData)
