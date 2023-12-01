
from flask import Blueprint, render_template, redirect, request
from user_management import check_logged_in
from device_info import *
from application_info import *
import subprocess
import re
import os

mynode_manage_apps = Blueprint('mynode_manage_apps',__name__)


### Page functions
@mynode_manage_apps.route("/apps")
def manage_apps_page():
    check_logged_in()

    t1 = get_system_time_in_ms()
    apps = get_all_applications(order_by="alphabetic")
    t2 = get_system_time_in_ms()
    # Load page
    templateData = {
        "title": "Manage Apps",
        "ui_settings": read_ui_settings(),
        "load_time": t2-t1,
        "product_key_skipped": skipped_product_key(),
        "apps": apps,
        "has_customized_app_versions": has_customized_app_versions(),
    }
    return render_template('manage_apps.html', **templateData)

@mynode_manage_apps.route("/apps/restart-app")
def restart_app_page():
    check_logged_in()

    # Check application specified
    if not request.args.get("app"):
        flash("No application specified", category="error")
        return redirect("/apps")
    
    # Check application name is valid
    app = request.args.get("app")
    if not is_application_valid(app):
        flash("Application is invalid", category="error")
        return redirect("/apps")

    if not restart_application(app):
        flash("Error restarting application!", category="error")
        return redirect("/apps")

    flash("Application restarting!", category="message")
    return redirect("/apps")

@mynode_manage_apps.route("/apps/customize-app-versions", methods=['GET','POST'])
def customize_app_versions_page():
    check_logged_in()

    apps = get_all_applications(order_by="alphabetic")
    app_version_data=get_app_version_data()
    custom_app_version_data=get_custom_app_version_data()

    # Reset Config
    if request.args.get("reset") and request.args.get("reset") == "1":
        reset_custom_app_version_data()
        flash("Custom config reset!", category="message")
        return redirect("/apps/customize-app-versions")

    # Save Config
    if request.method == 'POST' and request.form.get('app_data'):
        custom_app_data = request.form.get('app_data')
        save_custom_app_version_data(custom_app_data)
        flash("Custom config saved!", category="message")
        return redirect("/apps/customize-app-versions")

    # Load page
    templateData = {
        "title": "Customize App Versions",
        "ui_settings": read_ui_settings(),
        "product_key_skipped": skipped_product_key(),
        "apps": apps,
        "has_customized_app_versions": has_customized_app_versions(),
        "app_version_data": app_version_data,
        "custom_app_version_data": custom_app_version_data
    }
    return render_template('customize_app_versions.html', **templateData)

@mynode_manage_apps.route("/apps/save-app-version", methods=['POST'])
def save_app_version_page():
    check_logged_in()

    if not request.form.get("app") or not request.form.get("version"):
        flash("Missing data", category="error")
        return redirect("/apps/customize-app-versions")

    short_name = request.form.get("app")
    version = request.form.get("version")
    save_custom_app_version(short_name, version)

    flash("Application Version Saved!", category="message")
    return redirect("/apps/customize-app-versions")

@mynode_manage_apps.route("/apps/clear-app-version", methods=['POST'])
def clear_app_version_page():
    check_logged_in()

    if not request.form.get("app"):
        flash("Missing data", category="error")
        return redirect("/apps/customize-app-versions")

    short_name = request.form.get("app")
    clear_custom_app_version(short_name)

    flash("Custom Application Version Cleared!", category="message")
    return redirect("/apps/customize-app-versions")