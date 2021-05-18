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
def reinstall_app(app):
    if not is_upgrade_running():
        mark_upgrade_started()

        # Clear app data
        clear_application_cache()

        os.system("touch /tmp/skip_base_upgrades")
        os.system("sync")

        # Reinstall
        os.system("mkdir -p /home/admin/upgrade_logs")
        file1 = "/home/admin/upgrade_logs/reinstall_{}.txt".format(app)
        file2 = "/home/admin/upgrade_logs/upgrade_log_latest.txt"
        cmd = "/usr/bin/mynode_reinstall_app.sh {} 2>&1 | tee {} {}".format(app,file1, file2)
        subprocess.call(cmd, shell=True)
        
        # Sync
        os.system("sync")
        time.sleep(1)

        # Reboot
        reboot_device()

def uninstall_app(app):
    # Make sure app is disabled
    disable_service(app)

    # Clear app data
    clear_application_cache()

    # Uninstall App
    os.system("mkdir -p /home/admin/upgrade_logs")
    file1 = "/home/admin/upgrade_logs/uninstall_{}.txt".format(app)
    file2 = "/home/admin/upgrade_logs/uninstall_log_latest.txt"
    cmd = "/usr/bin/mynode_uninstall_app.sh {} 2>&1 | tee {} {}".format(app,file1, file2)
    subprocess.call(cmd, shell=True)
    
    # Sync
    os.system("sync")

def is_installed(short_name):
    filename1 = "/home/bitcoin/.mynode/"+short_name+"_install"
    filename2 = "/mnt/hdd/mynode/settings/"+short_name+"_install"
    if os.path.isfile(filename1):
        return True
    elif os.path.isfile(filename2):
        return True
    return False

def get_app_current_version(short_name):
    version = "unknown"
    filename1 = "/home/bitcoin/.mynode/"+short_name+"_version"
    filename2 = "/mnt/hdd/mynode/settings/"+short_name+"_version"
    if os.path.isfile(filename1):
        version = get_file_contents(filename1)
    elif os.path.isfile(filename2):
        version = get_file_contents(filename2)
    else:
        version = "not installed"

    # For versions that are hashes, shorten them
    version = version[0:16]

    return version

def get_app_latest_version(app):
    version = "unknown"
    filename1 = "/home/bitcoin/.mynode/"+app+"_version_latest"
    filename2 = "/mnt/hdd/mynode/settings/"+app+"_version_latest"
    if os.path.isfile(filename1):
        version = get_file_contents(filename1)
    elif os.path.isfile(filename2):
        version = get_file_contents(filename2)
    else:
        version = "error"

    # For versions that are hashes, shorten them
    version = version[0:16]

    return version

def create_application(name="NAME",
                       short_name="SHORT_NAME",
                       app_tile_name=None,
                       is_premium=False,
                       is_beta=False,
                       can_reinstall=True,
                       can_uninstall=False,
                       requires_lightning=False,
                       requires_electrs=False,
                       requires_bitcoin=False,
                       requires_docker_image_installation=False,
                       supports_testnet=False,
                       show_on_homepage=False,
                       show_on_application_page=True,
                       can_enable_disable=True,
                       homepage_order=9999,
                       homepage_section="",
                       app_tile_button_text=None,
                       app_tile_default_status_text="",
                       app_tile_running_status_text="",
                       app_tile_button_href="#",
                       status="UNKNOWN",
                       log_file=None,
                       journalctl_log_name=None,
                       ):
    app = {}
    app["name"] = name
    app["short_name"] = short_name
    if app_tile_name != None:
        app["app_tile_name"] = app_tile_name
    else:
        app["app_tile_name"] = name
    app["is_premium"] = is_premium
    app["current_version"] = get_app_current_version(short_name)
    app["latest_version"] = get_app_latest_version(short_name)
    app["is_beta"] = is_beta
    app["is_installed"] = is_installed(app["current_version"])
    app["can_reinstall"] = can_reinstall
    app["can_uninstall"] = can_uninstall
    app["requires_lightning"] = requires_lightning
    app["requires_electrs"] = requires_electrs
    app["requires_bitcoin"] = requires_bitcoin
    app["requires_docker_image_installation"] = requires_docker_image_installation
    app["supports_testnet"] = supports_testnet
    app["show_on_homepage"] = show_on_homepage
    app["show_on_application_page"] = show_on_application_page
    app["can_enable_disable"] = can_enable_disable
    app["is_enabled"] = is_service_enabled(short_name)
    #app["status"] = status # Should status be optional to include? Takes lots of time.
    #app["status_color"] = get_service_status_color(short_name)
    app["log_file"] = log_file
    app["journalctl_log_name"] = journalctl_log_name
    app["homepage_order"] = homepage_order
    app["homepage_section"] = homepage_section
    if app["homepage_section"] == "" and app["show_on_homepage"]:
        app["homepage_section"] = "apps"
    if app_tile_button_text != None:
        app["app_tile_button_text"] = app_tile_button_text
    else:
        app["app_tile_button_text"] = app["app_tile_name"]
    app["app_tile_default_status_text"] = app_tile_default_status_text
    if app_tile_running_status_text != "":
        app["app_tile_running_status_text"] = app_tile_running_status_text
    else:
        app["app_tile_running_status_text"] = app_tile_default_status_text
    app["app_tile_button_href"] = app_tile_button_href
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
        app_tile_running_status_text="Running",
        log_file=get_bitcoin_log_file()
    ))
    apps.append(create_application(
        name="LND",
        short_name="lnd",
        app_tile_running_status_text="Running",
    ))
    apps.append(create_application(
        name="Loop",
        short_name="loop",
        requires_lightning=True,
    ))
    apps.append(create_application(
        name="Pool",
        short_name="pool",
        requires_lightning=True,
    ))
    apps.append(create_application(
        name="Lightning Terminal",
        short_name="lit",
        requires_lightning=True,
    ))
    apps.append(create_application(
        name="Ride the Lightning",
        short_name="rtl",
        app_tile_name="RTL",
        app_tile_default_status_text="Lightning Wallet",
        can_uninstall=True,
        show_on_homepage=True,
        requires_lightning=True,
        supports_testnet=True,
        homepage_order=11
    ))
    apps.append(create_application(
        name="Electrum Server",
        short_name="electrs",
        app_tile_button_text="Info",
        app_tile_button_href="/electrum-server",
        app_tile_default_status_text="",
        app_tile_running_status_text="Running",
        can_reinstall=False,
        show_on_homepage=True,
        supports_testnet=True,
        homepage_order=12
    ))
    apps.append(create_application(
        name="BTCPay Server",
        short_name="btcpayserver",
        app_tile_default_status_text="Merchant Tool",
        can_uninstall=True,
        requires_lightning=True,
        show_on_homepage=True,
        homepage_order=13
    ))
    apps.append(create_application(
        name="Mempool",
        short_name="mempool",
        app_tile_default_status_text="Mempool Viewer",
        can_uninstall=True,
        show_on_homepage=True,
        supports_testnet=True,
        requires_docker_image_installation=True,
        homepage_order=14
    ))
    apps.append(create_application(
        name="LND Hub",
        short_name="lndhub",
        app_tile_default_status_text="BlueWallet Backend",
        can_uninstall=True,
        requires_lightning=True,
        show_on_homepage=True,
        homepage_order=15
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
        name="BTC RPC Explorer",
        short_name="btcrpcexplorer",
        app_tile_name="Explorer",
        app_tile_default_status_text="BTC RPC Explorer",
        can_uninstall=True,
        requires_bitcoin=True,
        show_on_homepage=True,
        supports_testnet=True,
        requires_electrs=True,
        homepage_order=21
    ))
    apps.append(create_application(
        name="Dojo",
        short_name="dojo",
        app_tile_button_text="Info",
        app_tile_button_href="/dojo",
        app_tile_default_status_text="Mixing Tool",
        app_tile_running_status_text="Running",
        can_uninstall=True,
        show_on_application_page=True,
        show_on_homepage=True,
        requires_electrs=True,
        requires_docker_image_installation=True,
        homepage_order=22
    ))
    apps.append(create_application(
        name="Whirlpool",
        short_name="whirlpool",
        app_tile_button_text="Info",
        app_tile_button_href="/whirlpool",
        app_tile_default_status_text="Mixing Tool",
        app_tile_running_status_text="Running",
        can_uninstall=True,
        show_on_homepage=True,
        homepage_order=23
    ))
    apps.append(create_application(
        name="JoininBox",
        short_name="joininbox",
        app_tile_button_text="Info",
        app_tile_button_href="/joininbox",
        app_tile_default_status_text="JoinMarket Mixing",
        can_uninstall=True,
        show_on_homepage=True,
        homepage_order=24,
        can_enable_disable=False,
        is_premium=True,
    ))
    apps.append(create_application(
        name="Joinmarket",
        short_name="joinmarket",
        show_on_application_page=False,
        is_premium=True
    ))
    apps.append(create_application(
        name="Thunderhub",
        short_name="thunderhub",
        app_tile_default_status_text="Lightning Wallet",
        can_uninstall=True,
        requires_lightning=True,
        supports_testnet=True,
        show_on_homepage=True,
        homepage_order=25,
        is_premium=True
    ))
    apps.append(create_application(
        name="Caravan",
        short_name="caravan",
        requires_bitcoin=True,
        app_tile_button_text="Info",
        app_tile_button_href="/caravan",
        app_tile_default_status_text="Multisig Tool",
        can_uninstall=True,
        show_on_homepage=True,
        homepage_order=31,
        supports_testnet=True,
        is_premium=True
    ))
    apps.append(create_application(
        name="Specter",
        short_name="specter",
        requires_bitcoin=True,
        app_tile_default_status_text="Multisig Tool",
        can_uninstall=True,
        show_on_homepage=True,
        homepage_order=32,
        supports_testnet=True,
        is_premium=True
    ))
    apps.append(create_application(
        name="CKBunker",
        short_name="ckbunker",
        requires_bitcoin=True,
        app_tile_default_status_text="Coldcard Signing Tool",
        can_uninstall=True,
        show_on_homepage=True,
        homepage_order=33,
        supports_testnet=True,
        is_premium=True
    ))
    apps.append(create_application(
        name="Sphinx Relay",
        short_name="sphinxrelay",
        app_tile_button_text="Info",
        app_tile_button_href="/sphinxrelay",
        app_tile_default_status_text="Sphinx Chat Backend",
        app_tile_running_status_text="Running",
        can_uninstall=True,
        requires_lightning=True,
        show_on_homepage=True,
        homepage_order=34,
        is_premium=True
    ))
    apps.append(create_application(
        name="LNbits",
        short_name="lnbits",
        requires_lightning=True,
        app_tile_default_status_text="Lightning Wallet",
        can_uninstall=True,
        show_on_homepage=True,
        homepage_order=35,
        is_premium=True
    ))
    # apps.append(create_application(
    #     name="WARden",
    #     short_name="warden",
    #     requires_lightning=False,
    #     app_tile_default_status_text="Bitcoin Portfolio",
    #     can_uninstall=True,
    #     show_on_homepage=True,
    #     homepage_order=41,
    #     is_premium=False
    # ))
    # apps.append(create_application(
    #     name="PyBlock",
    #     short_name="pyblock",
    #     requires_lightning=True,
    #     app_tile_default_status_text="Blockchain Info",
    #     app_tile_button_text="Info",
    #     app_tile_button_href="/pyblock",
    #     can_uninstall=True,
    #     can_enable_disable=False,
    #     show_on_homepage=True,
    #     homepage_order=42,
    #     is_premium=False
    # ))
    apps.append(create_application(
        name="Web SSH",
        short_name="webssh2",
    ))
    apps.append(create_application(
        name="Netdata",
        short_name="netdata",
        show_on_application_page=False
    ))
    apps.append(create_application(
        name="Tor",
        short_name="tor",
        can_enable_disable=False,
        app_tile_button_text="Tor Services",
        app_tile_default_status_text="Private Connections",
        app_tile_button_href="/tor",
        show_on_homepage=True,
        show_on_application_page=False,
        journalctl_log_name="tor@default",
        homepage_section="remote_services",
        supports_testnet=True,
        is_premium=True,
    ))
    apps.append(create_application(
        name="VPN",
        short_name="vpn",
        can_reinstall=False,
        app_tile_button_text="Info",
        app_tile_button_href="/vpn-info",
        show_on_homepage=True,
        show_on_application_page=False,
        homepage_section="remote_services",
        supports_testnet=True,
        is_premium=True,
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

def clear_application_cache():
    global mynode_applications
    mynode_applications = None

def get_all_applications(order_by="none"):
    global mynode_applications

    if mynode_applications == None:
        initialize_applications()
    else:
        update_applications()

    apps = copy.deepcopy(mynode_applications)
    if order_by == "alphabetic":
        apps.sort(key=lambda x: x["name"])
    elif order_by == "homepage":
        apps.sort(key=lambda x: x["homepage_order"])

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

def get_application_status_special(short_name):
    if short_name == "bitcoin":
        return get_bitcoin_status()
    elif short_name == "lnd":
        return get_lnd_status()
    elif short_name == "vpn":
        if os.path.isfile("/home/pivpn/ovpns/mynode_vpn.ovpn"):
            return "Running"
        else:
            return "Setting up..."
    elif short_name == "electrs":
        return get_electrs_status()
    elif short_name == "whirlpool":
        if not os.path.isfile("/mnt/hdd/mynode/whirlpool/whirlpool-cli-config.properties"):
            return "Waiting for initialization..."
    elif short_name == "dojo":
        try:
            dojo_initialized = subprocess.check_output("docker inspect --format={{.State.Running}} db", shell=True).strip()
        except:
            dojo_initialized = ""
        if dojo_initialized != "true":
            return "Error"
    return ""

def get_application_status(short_name):
    # Make sure app is valid
    if not is_application_valid(short_name):
        return "APP NOT FOUND"
    
    # Get application
    app = get_application(short_name)

    # Check Disabled, Testnet, Lightning, Electrum requirements...
    if is_testnet_enabled() and not app["supports_testnet"]:
        return "Requires Mainnet"
    if app["requires_docker_image_installation"] and is_installing_docker_images():
        return "Installing..."
    if app["requires_lightning"] and not is_lnd_ready():
        return "Waiting on Lightning"
    if not app["is_enabled"]:
        return app["app_tile_default_status_text"]
    if app["requires_bitcoin"] and not is_bitcoin_synced():
        return "Waiting on Bitcoin"
    if app["requires_electrs"] and not is_electrs_active():
        return "Waiting on Electrum"

    # Check special cases
    special_status = get_application_status_special(short_name)
    if special_status != "":
        return special_status

    # Return
    return app["app_tile_running_status_text"]

def get_application_status_color_special(short_name):
    if short_name == "lnd":
        return get_lnd_status_color()
    elif short_name == "joininbox":
        return "clear"
    elif short_name == "pyblock":
        return "clear"
    elif short_name == "whirlpool":
        if not os.path.isfile("/mnt/hdd/mynode/whirlpool/whirlpool-cli-config.properties"):
            return "yellow"
    elif short_name == "dojo":
        try:
            dojo_initialized = subprocess.check_output("docker inspect --format={{.State.Running}} db", shell=True).strip()
        except:
            dojo_initialized = ""
        if dojo_initialized != "true":
            return "red"
    return ""

def get_application_status_color(short_name):
    # Make sure app is valid
    if not is_application_valid(short_name):
        return "gray"
    
    # Get application
    app = get_application(short_name)

    # Check Disabled, Testnet, Lightning, Electrum requirements...
    if is_testnet_enabled() and not app["supports_testnet"]:
        return "gray"
    if app["requires_docker_image_installation"] and is_installing_docker_images():
        return "yellow"
    if app["requires_lightning"] and not is_lnd_ready():
        return "gray"
    if app["can_enable_disable"] and not app["is_enabled"]:
        return "gray"
    if app["requires_bitcoin"] and not is_bitcoin_synced():
        return "yellow"
    if app["requires_electrs"] and not is_electrs_active():
        return "yellow"

    # Check special cases
    special_status_color = get_application_status_color_special(short_name)
    if special_status_color != "":
        return special_status_color

    # Return service operational status
    return get_service_status_color(short_name)

def get_application_sso_token(short_name):
    # Make sure app is valid
    if not is_application_valid(short_name):
        return "APP NOT FOUND"
    
    if short_name == "btcrpcexplorer":
        return get_btcrpcexplorer_sso_token()
    if short_name == "thunderhub":
        return get_thunderhub_sso_token()
    return ""

def restart_application(short_name):
    try:
        subprocess.check_output('systemctl restart {}'.format(short_name), shell=True)
        return True
    except Exception as e:
        return False