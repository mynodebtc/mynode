
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

    categories = [{"name": "core", "title": "Core Apps"},
                  {"name": "bitcoin_app", "title": "Bitcoin Apps"},
                  {"name": "lightning_app", "title": "Lightning Apps"},
                  {"name": "communication", "title": "Communication"},
                  {"name": "networking", "title": "Networking"},
                  {"name": "device_management", "title": "Device Management Apps"},
                  {"name": "uncategorized", "title": "Uncategorized"}
                ]

    # Counts for the filter buttons, over the apps the page lists
    category_names = [c["name"] for c in categories]
    listed_apps = [a for a in apps if a["show_on_marketplace_page"] and a["category"] in category_names]
    filter_counts = {
        "all": len(listed_apps),
        "installed": len([a for a in listed_apps if a["is_installed"]]),
        "not_installed": len([a for a in listed_apps if not a["is_installed"]]),
        "pinned": len([a for a in listed_apps if a["has_custom_version"]]),
        "beta": len([a for a in listed_apps if a["is_beta"]]),
        "categories": {name: len([a for a in listed_apps if a["category"] == name]) for name in category_names},
    }

    # Load page
    templateData = {
        "title": "Marketplace",
        "ui_settings": read_ui_settings(),
        "load_time": t2-t1,
        "product_key_skipped": skipped_product_key(),
        "categories": categories,
        "filter_counts": filter_counts,
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
        "title": app["name"],
        "ui_settings": read_ui_settings(),
        "product_key_skipped": skipped_product_key(),
        "app_status": app_status,
        "app": app
    }
    return render_template('/marketplace_app.html', **templateData)
