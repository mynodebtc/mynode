
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

    # Load page
    templateData = {
        "title": "MyNode Marketplace",
        "ui_settings": read_ui_settings(),
        "load_time": t2-t1,
        "product_key_skipped": skipped_product_key(),
        "categories": categories,
        "apps": apps,
        "has_customized_app_versions": has_customized_app_versions(),
    }
    return render_template('marketplace.html', **templateData)

@mynode_marketplace.route("/marketplace/add_app", methods=['GET','POST'])
def marketplace_add_app_page():
    check_logged_in()

    # Load page (no form submission)
    if request.method == 'GET':
        templateData = {
            "title": "MyNode - Add Community Application",
            "ui_settings": read_ui_settings(),
            "product_key_skipped": skipped_product_key()
        }
        return render_template('/marketplace_add_app.html', **templateData)

    # Submit was hit
    add_app_tmp_path = "/tmp/add_app/"
    add_app_tarball_path = "/tmp/add_app/app.tar.gz"
    run_linux_cmd("rm -rf " + add_app_tmp_path)
    run_linux_cmd("mkdir " + add_app_tmp_path)

    if 'app_tarball' in request.files and request.files['app_tarball'] != "":
        f = request.files['app_tarball']
        if f.filename != "":
            f.save( add_app_tarball_path )
    else:
        flash("Missing Application Tarball!", category="error")
        return redirect("/marketplace/add_app")

    # Extract and load app
    try:
        # Get basic app info
        app_short_name = "unknown_app_name"
        run_linux_cmd("tar --exclude='.[^/]*' -xf {} -C {}".format(add_app_tarball_path, add_app_tmp_path))
        for f in os.listdir(add_app_tmp_path):
            if os.path.isdir(add_app_tmp_path + "/" + f):
                app_short_name = f
        if app_short_name == "app_short_name":
            flash("Error Finding App Name".format(str(e)), category="error")
            return redirect("/marketplace/add_app")

        # Load app info
        app_info = {}
        app_json_path = "/tmp/add_app/{}/{}.json".format(app_short_name, app_short_name)
        with open(app_json_path, 'r') as fp:
            app_info = json.load(fp)

        # Copy app to app folder
        run_linux_cmd("rm -rf /usr/share/mynode_apps/{}".format(app_short_name))
        run_linux_cmd("cp -r /tmp/add_app/{} /usr/share/mynode_apps/".format(app_short_name))
        run_linux_cmd("touch /usr/share/mynode_apps/{}/is_manually_added".format(app_short_name))
        run_linux_cmd("sync")

        # Init new/updated app
        init_dynamic_apps(app_short_name)

        # Redirect to app page?
        flash("{} Added!".format(app_info["name"]), category="message")
        return redirect("/marketplace/{}".format(app_short_name))
    except Exception as e:
        flash("Error Adding Application! {}".format(str(e)), category="error")
        return redirect("/marketplace/add_app")

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
        "title": "MyNode - " + app["name"],
        "ui_settings": read_ui_settings(),
        "product_key_skipped": skipped_product_key(),
        "app_status": app_status,
        "app": app
    }
    return render_template('/marketplace_app.html', **templateData)
