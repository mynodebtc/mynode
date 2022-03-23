from bitcoin_info import *
from lightning_info import *
from electrum_info import *
from device_info import *
from systemctl_info import *
from utilities import *
import copy
import json
import time
import subprocess
import re
import os

# Globals
DYNAMIC_APPLICATIONS_FOLDER = "/usr/share/mynode_apps"

# Cached data
JSON_APPLICATION_CACHE_FILE = "/tmp/app_cache.json"
mynode_applications = None

# Utility functions
def reinstall_app(app):
    if not is_upgrade_running():
        mark_upgrade_started()

        # Clear app data
        clear_application_cache()

        touch("/tmp/skip_base_upgrades")

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
    filename1 = "/home/bitcoin/.mynode/install_"+short_name
    filename2 = "/mnt/hdd/mynode/settings/install_"+short_name
    if os.path.isfile(filename1):
        return True
    elif os.path.isfile(filename2):
        return True
    return False

def get_app_current_version_from_file(short_name):
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

    return to_string(version)

def get_app_latest_version_from_file(app):
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

    return to_string(version)

def initialize_application_defaults(app):
    if not "name" in app: app["name"] = "NO_NAME"
    if not "short_name" in app: app["short_name"] = "NO_SHORT_NAME"
    if not "description" in app: app["description"] = ""
    if not "screenshots" in app: app["screenshots"] = []
    if not "app_tile_name" in app: app["app_tile_name"] = app["name"]
    if not "is_premium" in app: app["is_premium"] = False
    if not "current_version" in app: app["current_version"] = get_app_current_version_from_file( app["short_name"] )
    if not "latest_version" in app: app["latest_version"] = get_app_latest_version_from_file( app["short_name"] )
    if not "is_beta" in app: app["is_beta"] = False
    app["is_installed"] = is_installed( app["short_name"] )
    if not "can_reinstall" in app: app["can_reinstall"] = True
    if not "can_uninstall" in app: app["can_uninstall"] = False
    if not "requires_lightning" in app: app["requires_lightning"] = False
    if not "requires_electrs" in app: app["requires_electrs"] = False
    if not "requires_bitcoin" in app: app["requires_bitcoin"] = False
    if not "requires_docker_image_installation" in app: app["requires_docker_image_installation"] = False
    if not "supports_testnet" in app: app["supports_testnet"] = False
    if not "show_on_homepage" in app: app["show_on_homepage"] = False
    if not "show_on_application_page" in app: app["show_on_application_page"] = True
    if not "can_enable_disable" in app: app["can_enable_disable"] = True
    if not "is_enabled" in app: app["is_enabled"] = is_service_enabled( app["short_name"] )
    #app["status"] = get_application_status( app["short_name"] )
    #app["status_color"] = get_service_status_color( app["short_name"] )
    if not "hide_status_icon" in app: app["hide_status_icon"] = False
    if not "log_file" in app: app["log_file"] = get_application_log_file( app["short_name"] )
    if not "journalctl_log_name" in app: app["journalctl_log_name"] = None
    if not "homepage_order" in app: app["homepage_order"] = 9999
    if not "homepage_section" in app: app["homepage_section"] = ""
    if app["homepage_section"] == "" and app["show_on_homepage"]:
        app["homepage_section"] = "apps"
    if not "app_tile_button_text" in app: app["app_tile_button_text"] = app["app_tile_name"]
    if not "app_tile_default_status_text" in app: app["app_tile_default_status_text"] = ""
    if not "app_tile_running_status_text" in app: app["app_tile_running_status_text"] = app["app_tile_default_status_text"]
    if not "app_tile_button_href" in app: app["app_tile_button_href"] = "#"

    return app

def update_application(app, include_status=False):
    short_name = app["short_name"]
    app["is_enabled"] = is_service_enabled(short_name)
    if include_status:
        app["status"] = get_application_status( app["short_name"] )
        app["status_color"] = get_service_status_color( app["short_name"] )

def initialize_applications():
    global mynode_applications
    apps = []

    # Update latest version files
    os.system("/usr/bin/mynode_update_latest_version_files.sh")

    # Opening JSON file
    with open('/usr/share/mynode/application_info.json', 'r') as app_info_file:
        apps = json.load(app_info_file)
        
        for index, app in enumerate(apps):
            apps[index] = initialize_application_defaults(app)

        mynode_applications = copy.deepcopy(apps)

    # TODO: Load all app-specific JSON files
    # ...
    return

def update_applications(include_status=False):
    global mynode_applications

    for app in mynode_applications:
        update_application(app, include_status)

def clear_application_cache():
    global mynode_applications
    mynode_applications = None

def trigger_application_refresh():
    touch("/tmp/need_application_refresh")

def need_application_refresh():
    global mynode_applications
    if mynode_applications == None:
        return True
    if os.path.isfile("/tmp/need_application_refresh"):
        os.system("rm /tmp/need_application_refresh")
        os.system("sync")
        return True
    return False

def get_all_applications(order_by="none", include_status=False):
    global mynode_applications

    if need_application_refresh():
        initialize_applications()
    else:
        update_applications()

    if include_status:
        update_applications(include_status)

    apps = copy.deepcopy(mynode_applications)
    if order_by == "alphabetic":
        apps.sort(key=lambda x: x["name"])
    elif order_by == "homepage":
        apps.sort(key=lambda x: x["homepage_order"])

    return apps

# Only call this from the www python process so status data is available
def update_application_json_cache():
    global JSON_APPLICATION_CACHE_FILE
    apps = get_all_applications(order_by="alphabetic", include_status=True)
    return set_dictionary_file_cache(apps, JSON_APPLICATION_CACHE_FILE)

# Getting the data can be called from any process
def get_all_applications_from_json_cache():
    global JSON_APPLICATION_CACHE_FILE
    return get_dictionary_file_cache(JSON_APPLICATION_CACHE_FILE)

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
        elif short_name == "usb_extras":
            return get_journalctl_log("usb_extras")
        elif short_name == "www":
            return get_journalctl_log("www")
        else:
            return "ERROR: App or log not found ({})".format(short_name)

def get_application_log_file(short_name):
    if short_name == "bitcoin":
        return get_bitcoin_log_file()
    return None

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
            dojo_initialized = to_string(subprocess.check_output("docker inspect --format={{.State.Running}} db", shell=True).strip())
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
    if app["requires_electrs"] and not is_electrs_active():
        return "Waiting on Electrum"
    if not app["is_enabled"]:
        return to_string(app["app_tile_default_status_text"])
    if app["requires_bitcoin"] and not is_bitcoin_synced():
        return "Waiting on Bitcoin"


    # Check special cases
    special_status = get_application_status_special(short_name)
    if special_status != "":
        return special_status

    # Return
    return app["app_tile_running_status_text"]

def get_application_status_color_special(short_name):
    if short_name == "lnd":
        return get_lnd_status_color()
    elif short_name == "whirlpool":
        if not os.path.isfile("/mnt/hdd/mynode/whirlpool/whirlpool-cli-config.properties"):
            return "yellow"
    elif short_name == "dojo":
        try:
            dojo_initialized = to_string(subprocess.check_output("docker inspect --format={{.State.Running}} db", shell=True).strip())
        except:
            dojo_initialized = ""
        if dojo_initialized != "true":
            return "red"
    elif short_name == "premium_plus":
        if has_premium_plus_token():
            if get_premium_plus_is_connected():
                return "green"
            else:
                return "red"
        else:
            return "gray"
    return ""

def get_application_status_color(short_name):
    # Make sure app is valid
    if not is_application_valid(short_name):
        return "gray"
    
    # Get application
    app = get_application(short_name)

    # Check hidden icon
    if app["hide_status_icon"]:
        return "clear"

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
        return "APP_NOT_FOUND"
    return get_sso_token(short_name)

def get_application_sso_token_enabled(short_name):
    # Make sure app is valid
    if not is_application_valid(short_name):
        return "APP_NOT_FOUND"
    return get_sso_token_enabled(short_name)

def restart_application(short_name):
    try:
        subprocess.check_output('systemctl restart {}'.format(short_name), shell=True)
        return True
    except Exception as e:
        return False

def has_customized_app_versions():
    if os.path.isfile("/usr/share/mynode/mynode_app_versions_custom.sh"):
        return True
    if os.path.isfile("/mnt/hdd/mynode/settings/mynode_app_versions_custom.sh"):
        return True
    return False

def get_app_version_data():
    try:
        contents = to_string(subprocess.check_output('cat /usr/share/mynode/mynode_app_versions.sh | grep -v "_VERSION_FILE=" | grep "="', shell=True))
        return contents
    except Exception as e:
        return "ERROR"

def get_custom_app_version_data():
    if os.path.isfile("/usr/share/mynode/mynode_app_versions_custom.sh"):
        return to_string( get_file_contents("/usr/share/mynode/mynode_app_versions_custom.sh") )
    if os.path.isfile("/mnt/hdd/mynode/settings/mynode_app_versions_custom.sh"):
        return to_string( get_file_contents("/mnt/hdd/mynode/settings/mynode_app_versions_custom.sh") )
    return ""

def save_custom_app_version_data(data):
    set_file_contents("/usr/share/mynode/mynode_app_versions_custom.sh", data)
    set_file_contents("/mnt/hdd/mynode/settings/mynode_app_versions_custom.sh", data)
    os.system("sync")
    trigger_application_refresh()

def reset_custom_app_version_data():
    os.system("rm -f /usr/share/mynode/mynode_app_versions_custom.sh")
    os.system("rm -f /mnt/hdd/mynode/settings/mynode_app_versions_custom.sh")
    os.system("sync")
    trigger_application_refresh()

######################################################################################
## Dynamic Apps
######################################################################################
def get_dynamic_app_dir():
    global DYNAMIC_APPLICATIONS_FOLDER
    return DYNAMIC_APPLICATIONS_FOLDER

def get_dynamic_app_names():
    app_dir = get_dynamic_app_dir()
    app_names = []
    for app_folder_name in os.listdir( app_dir ):
        if os.path.isdir(app_dir + "/" +app_folder_name):
            app_names.append(app_folder_name)
    return app_names

def init_dynamic_app(app_info):
    app_name = app_info["short_name"]
    app_dir = DYNAMIC_APPLICATIONS_FOLDER + "/" + app_name
    log_message(" Loading " + app_name + "...")
    os.system("cp -f {} {}".format(app_dir+"/app.service", "/etc/systemd/system/"+app_name+".service"))
    os.system("cp -f {} {}".format(app_dir+"/"+app_name+".png", "/var/www/mynode/static/images/app_icons/"+app_name+".png"))
    if (os.path.isfile(app_dir+"/scripts/pre_"+app_name+".sh")):
        os.system("cp -f {} {}".format(app_dir+"/scripts/pre_"+app_name+".sh",      "/usr/bin/service_post/pre_"+app_name+".sh"))
    if (os.path.isfile(app_dir+"/scripts/post_"+app_name+".sh")):
        os.system("cp -f {} {}".format(app_dir+"/scripts/post_"+app_name+".sh",     "/usr/bin/service_pre/post_"+app_name+".sh"))
    if (os.path.isfile(app_dir+"/scripts/install"+app_name+".sh")):
        os.system("cp -f {} {}".format(app_dir+"/scripts/install_"+app_name+".sh",  "/usr/bin/service_install/install_"+app_name+".sh"))
    if (os.path.isfile(app_dir+"/scripts/uninstall"+app_name+".sh")):
        os.system("cp -f {} {}".format(app_dir+"/scripts/uninstall"+app_name+".sh", "/usr/bin/service_uninstall/uninstall_"+app_name+".sh"))
    
    log_message("  TODO: Install data files")

    # For "node" type apps
    log_message("  TODO: Need node special files???")

    # For "python" type apps
    log_message("  TODO: Need python special files???")

    # For "docker" type apps
    log_message("  TODO: Build dockerfile???")
    log_message("  TODO: Install dockerfile???")

    log_message(" Done.")

def init_dynamic_apps():
    # Loop over each app
    root_app_dir = get_dynamic_app_dir()
    app_names = get_dynamic_app_names()
    for app_name in app_names:
        log_message("Found Application: {}".format(app_name))
        app_dir = root_app_dir + "/" + app_name
        try:
            app_json_path = app_dir + "/app.json"
            with open(app_json_path, 'r') as fp:
                app_info = json.load(fp)
                init_dynamic_app(app_info)

        except Exception as e:
            log_message("  ERROR: Error loading app.json file ({})".format(str(e)))            

    os.system("systemctl daemon-reload")