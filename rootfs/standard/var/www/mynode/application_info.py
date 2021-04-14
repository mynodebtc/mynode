from bitcoin_info import *
from lightning_info import *
from electrum_info import *
from device_info import *
from systemctl_info import *
import copy
import json
import subprocess
import re
import os

# Cached data
mynode_applications = None

# Utility functions
def is_installed(current_version):
    return current_version != "not installed"

def create_application(name="NAME",
                       short_name="SHORT_NAME",
                       is_premium=False,
                       can_reinstall=True,
                       can_uninstall=False,
                       show_on_homepage=False,
                       show_on_application_page=True,
                       can_enable_disable=True,
                       icon="TODO",
                       status="UNKNOWN",
                       log_file=None,
                       journalctl_log_name=None):
    app = {}
    app["name"] = name
    app["short_name"] = short_name
    app["is_premium"] = is_premium
    app["current_version"] = get_app_current_version(short_name)
    app["latest_version"] = get_app_latest_version(short_name)
    app["is_installed"] = is_installed(app["current_version"])
    app["can_reinstall"] = can_reinstall
    app["can_uninstall"] = can_uninstall
    app["show_on_homepage"] = show_on_homepage
    app["show_on_application_page"] = show_on_application_page
    app["can_enable_disable"] = can_enable_disable
    app["is_enabled"] = is_service_enabled(short_name)
    app["icon"] = icon
    #app["status"] = status # Should status be optional to include? Takes lots of time.
    #app["status_color"] = get_service_status_color(short_name)
    app["log_file"] = log_file
    app["journalctl_log_name"] = journalctl_log_name
    return app

def update_application(app):
    short_name = app["short_name"]
    app["is_enabled"] = is_service_enabled(short_name)
    #app["status"] = "???" # Should status be optional to include? Takes lots of time.
    #app["status_color"] = get_service_status_color(short_name)

def initialize_applications():
    global mynode_applications
    apps = []

    apps.append(create_application(
        name="Bitcoin",
        short_name="bitcoin",
        log_file=get_bitcoin_log_file()
    ))
    apps.append(create_application(
        name="LND",
        short_name="lnd",
    ))
    apps.append(create_application(
        name="Loop",
        short_name="loop",
    ))
    apps.append(create_application(
        name="Pool",
        short_name="pool",
    ))
    apps.append(create_application(
        name="Lightning Terminal",
        short_name="lit",
    ))
    apps.append(create_application(
        name="Electrum Server",
        short_name="electrs",
        can_reinstall=False,
        show_on_homepage=True
    ))
    apps.append(create_application(
        name="BTC RPC Explorer",
        short_name="btcrpcexplorer",
        show_on_homepage=True
    ))
    apps.append(create_application(
        name="Corsproxy",
        short_name="corsproxy",
        can_enable_disable=False,
        show_on_application_page=False
    ))
    apps.append(create_application(
        name="LNDConnect",
        short_name="lndconnect",
    ))
    apps.append(create_application(
        name="LND Hub",
        short_name="lndhub",
        show_on_homepage=True
    ))
    apps.append(create_application(
        name="Ride the Lightning",
        short_name="rtl",
        show_on_homepage=True
    ))
    apps.append(create_application(
        name="BTCPay Server",
        short_name="btcpayserver",
        show_on_homepage=True
    ))
    apps.append(create_application(
        name="Mempool",
        short_name="mempool",
        show_on_homepage=True
    ))
    apps.append(create_application(
        name="Whirlpool",
        short_name="whirlpool",
        show_on_homepage=True
    ))
    apps.append(create_application(
        name="Dojo",
        short_name="dojo",
        show_on_application_page=True,
        show_on_homepage=True
    ))
    apps.append(create_application(
        name="Joinmarket",
        short_name="joinmarket",
        show_on_homepage=True,
        is_premium=True
    ))
    apps.append(create_application(
        name="JoininBox",
        short_name="joininbox",
        show_on_homepage=True,
        can_enable_disable=False,
        is_premium=True,
    ))
    apps.append(create_application(
        name="Thunderhub",
        short_name="thunderhub",
        show_on_homepage=True,
        is_premium=True
    ))
    apps.append(create_application(
        name="LNbits",
        short_name="lnbits",
        show_on_homepage=True,
        is_premium=True
    ))
    apps.append(create_application(
        name="Caravan",
        short_name="caravan",
        show_on_homepage=True,
        is_premium=True
    ))
    apps.append(create_application(
        name="Specter",
        short_name="specter",
        show_on_homepage=True,
        is_premium=True
    ))
    apps.append(create_application(
        name="CKBunker",
        short_name="ckbunker",
        show_on_homepage=True,
        is_premium=True
    ))
    apps.append(create_application(
        name="Sphinx Relay",
        short_name="sphinxrelay",
        show_on_homepage=True,
        is_premium=True
    ))
    apps.append(create_application(
        name="Web SSH",
        short_name="webssh2"
    ))
    apps.append(create_application(
        name="Netdata",
        short_name="netdata",
        show_on_application_page=False
    ))
    apps.append(create_application(
        name="Tor",
        short_name="tor",
        show_on_application_page=False,
        journalctl_log_name="tor@default"
    ))
    apps.append(create_application(
        name="VPN",
        short_name="vpn",
        show_on_homepage=True,
        can_reinstall=False,
        show_on_application_page=False
    ))
    apps.append(create_application(
        name="NGINX",
        short_name="nginx",
        show_on_application_page=False
    ))
    apps.append(create_application(
        name="Firewall",
        short_name="ufw",
        show_on_application_page=False,
        journalctl_log_name="ufw"
    ))
    mynode_applications = copy.deepcopy(apps)

def update_applications():
    global mynode_applications

    for app in mynode_applications:
        update_application(app)

def get_all_applications(order_by="none"):
    global mynode_applications

    if mynode_applications == None:
        initialize_applications()
    else:
        update_applications()

    apps = copy.deepcopy(mynode_applications)
    if order_by == "alphabetic":
        apps.sort(key=lambda x: x["name"])

    return apps

def get_application(short_name):
    apps = get_all_applications()
    for app in apps:
        if app["short_name"] == short_name:
            return app
    return None

def is_application_valid(short_name):
    apps = get_all_applications()
    for app in apps:
        if app["short_name"] == short_name:
            return True
    return False

# Application Functions
def get_application_log(short_name):
    app = get_application(short_name)
    if app:
        if app["log_file"] != None:
            return get_file_log( app["log_file"] )
        elif app["journalctl_log_name"] != None:
            return get_journalctl_log( app["journalctl_log_name"] )            
        else:
            return get_journalctl_log(short_name)
    else:
        # Log may be custom / non-app service
        if short_name == "startup":
            return get_journalctl_log("mynode")
        elif short_name == "quicksync":
            return get_quicksync_log()
        elif short_name == "docker":
            return get_journalctl_log("docker")
        elif short_name == "docker_image_build":
            return get_journalctl_log("docker_images")
        else:
            return "ERROR: App or log not found ({})".format(short_name)
