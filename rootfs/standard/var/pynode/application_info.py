from bitcoin_info import *
from lightning_info import *
from electrum_info import *
from dojo_info import *
from device_info import *
from drive_info import *
from systemctl_info import *
from utilities import *
import copy
import json
import time
import subprocess
import importlib
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

def remove_app(app):
    # Remove install markers
    clear_app_installed(app)

    # Make sure app is disabled
    disable_service(app)

    # Clear app data
    clear_application_cache()

    # Remove App
    os.system("rm -rf /usr/share/mynode_apps/{}".format(app))
    os.system("sync")

def is_installed(short_name):
    filename1 = "/home/bitcoin/.mynode/install_"+short_name
    filename2 = "/mnt/hdd/mynode/settings/install_"+short_name
    if os.path.isfile(filename1):
        return True
    elif os.path.isfile(filename2):
        return True
    return False

def mark_app_installed(short_name):
    install_marker_1 = "/home/bitcoin/.mynode/install_"+short_name
    install_marker_2 = "/mnt/hdd/mynode/settings/install_"+short_name
    latest_version_1 = "/home/bitcoin/.mynode/"+short_name+"_version_latest"
    latest_version_2 = "/mnt/hdd/mynode/settings/"+short_name+"_version_latest"
    # Check the latest version location
    if os.path.isfile(latest_version_1):
        touch(install_marker_1)
    elif os.path.isfile(latest_version_2):
        touch(install_marker_2)
    else:
        # App maybe dyanmic app (no version latest file) so mark sd card
        touch(install_marker_1)

def clear_app_installed(short_name):
    install_marker_1 = "/home/bitcoin/.mynode/install_"+short_name
    install_marker_2 = "/mnt/hdd/mynode/settings/install_"+short_name
    delete_file(install_marker_1)
    delete_file(install_marker_2)

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
    short_name = app["short_name"]
    version = "unknown"

    # Check for custom version
    filename1_custom = "/home/bitcoin/.mynode/"+short_name+"_version_latest_custom"
    filename2_custom = "/mnt/hdd/mynode/settings/"+short_name+"_version_latest_custom"
    if os.path.isfile(filename1_custom):
        version = get_file_contents(filename1_custom)
    elif os.path.isfile(filename2_custom):
        version = get_file_contents(filename2_custom)
    else:
        # Check for official version in file
        filename1 = "/home/bitcoin/.mynode/"+short_name+"_version_latest"
        filename2 = "/mnt/hdd/mynode/settings/"+short_name+"_version_latest"
        if os.path.isfile(filename1):
            version = get_file_contents(filename1)
        elif os.path.isfile(filename2):
            version = get_file_contents(filename2)
        else:
            # Check for official version in JSON
            if "latest_version" in app:
                version = app["latest_version"]
            else:
                version = "error"

    # For versions that are hashes, shorten them
    version = version[0:16]

    return to_string(version)

def get_app_screenshots(short_name):
    screenshots = []
    screenshot_folder = "/var/www/mynode/static/images/screenshots/{}/".format(short_name)
    if os.path.isdir(screenshot_folder):
        for s in os.listdir(screenshot_folder):
            if s.endswith(".png"):
                screenshots.append(s)
        return sorted(screenshots)
    return screenshots

def replace_app_info_variables(app_data, text):
    text = text.replace("{VERSION}", app_data["latest_version"])
    text = text.replace("{SHORT_NAME}", app_data["short_name"])
    if app_data["http_port"] != None:
        text = text.replace("{HTTP_PORT}", str(app_data["http_port"]))
    if app_data["https_port"] != None:
        text = text.replace("{HTTPS_PORT}", str(app_data["https_port"]))
    text = text.replace("{APP_TOR_ADDRESS}", get_onion_url_for_service(app_data["short_name"]))
    text = text.replace("{LOCAL_IP_ADDRESS}", get_local_ip())
    return text

def get_app_not_supported_reason(app):
    if get_debian_version() < app["minimum_debian_version"]:
        return "Requires Debian "+app["minimum_debian_version"]+"+"
    return ""

def is_app_supported(app):
    return get_app_not_supported_reason(app) == ""

def initialize_application_defaults(app):
    if not "name" in app: app["name"] = "NO_NAME"
    if not "short_name" in app: app["short_name"] = "NO_SHORT_NAME"
    if not "app_type" in app: app["app_type"] = "custom"
    if not "category" in app: app["category"] = "uncategorized"
    if not "author" in app: app["author"] = {"name": "", "link": ""}
    if not "website" in app: app["website"] = {"name": "", "link": ""}
    if not "short_description" in app: app["short_description"] = "MISSING"
    if not "description" in app: app["description"] = []
    if not "screenshots" in app: app["screenshots"] = get_app_screenshots( app["short_name"] )
    if not "app_tile_name" in app: app["app_tile_name"] = app["name"]
    if not "linux_user" in app: app["linux_user"] = "bitcoin"
    if not "supported_archs" in app: app["supported_archs"] = None 
    if not "minimum_debian_version" in app: app["minimum_debian_version"] = 10
    if not "download_skip" in app: app["download_skip"] = False
    if not "download_type" in app: app["download_type"] = "source"      # source or binary
    if not "download_source_url" in app: app["download_source_url"] = "not_specified"
    if not "download_binary_url" in app: app["download_binary_url"] = {}    # Expected to be dictionary of "arch" : "url"
    app["install_folder"] = "/opt/mynode/{}".format(app["short_name"])
    app["storage_folder"] = "/mnt/hdd/mynode/{}".format(app["short_name"])
    if not "install_env_vars" in app: app["install_env_vars"] = {}
    if not "http_port" in app: app["http_port"] = None
    if not "https_port" in app: app["https_port"] = None
    if not "extra_ports" in app: app["extra_ports"] = []
    if not "tor_address" in app: app["tor_address"] = get_onion_url_for_service( app["short_name"] )
    if not "is_premium" in app: app["is_premium"] = False
    if not "current_version" in app: app["current_version"] = get_app_current_version_from_file( app["short_name"] )
    app["latest_version"] = get_app_latest_version_from_file( app )
    if not "has_custom_version" in app: app["has_custom_version"] = has_custom_app_version( app["short_name"] )
    if not "is_beta" in app: app["is_beta"] = False
    app["is_installed"] = is_installed( app["short_name"] )
    app["is_manually_added"] = os.path.isfile("/usr/share/mynode_apps/{}/is_manually_added".format(app["short_name"]))
    if not "can_reinstall" in app: app["can_reinstall"] = True
    if not "can_uninstall" in app: app["can_uninstall"] = False
    if not "requires_lightning" in app: app["requires_lightning"] = False
    if not "requires_electrs" in app: app["requires_electrs"] = False
    if not "requires_bitcoin" in app: app["requires_bitcoin"] = False
    if not "requires_docker_image_installation" in app: app["requires_docker_image_installation"] = False
    if not "supports_testnet" in app: app["supports_testnet"] = False
    if not "show_on_homepage" in app: app["show_on_homepage"] = False
    if not "show_on_application_page" in app: app["show_on_application_page"] = True
    if not "show_on_marketplace_page" in app: app["show_on_marketplace_page"] = app["show_on_application_page"]
    if not "show_on_status_page" in app: app["show_on_status_page"] = False             # New apps should set to true
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
    if not "app_tile_running_status_text" in app: app["app_tile_running_status_text"] = app["short_description"]
    if not "app_tile_button_href" in app: app["app_tile_button_href"] = "#"
    if not "app_tile_button_onclick" in app: app["app_tile_button_onclick"] = ""
    if not "app_page_show_open_button" in app: app["app_page_show_open_button"] = True
    if not "app_page_additional_buttons" in app: app["app_page_additional_buttons"] = []
    if not "app_page_content" in app: app["app_page_content"] = []

    # Update fields that may use variables that need replacing, like {VERSION}, {SHORT_NAME}, etc...
    app["download_source_url"] = replace_app_info_variables(app, app["download_source_url"])
    for arch in app["download_binary_url"]:
        app["download_binary_url"][arch] = replace_app_info_variables(app, app["download_binary_url"][arch])
    app["app_tile_button_onclick"] = replace_app_info_variables(app, app["app_tile_button_onclick"])
    for btn in app["app_page_additional_buttons"]:
        if "onclick" in btn:
            btn["onclick"] = replace_app_info_variables(app, btn["onclick"])
    for key in app["install_env_vars"]:
        app["install_env_vars"][key] = replace_app_info_variables(app, app["install_env_vars"][key])
    for i,section in enumerate(app["app_page_content"]):
        for j,line in enumerate(section["content"]):
            section["content"][j] = replace_app_info_variables(app, line)
        app["app_page_content"][i] = section

    # Check if app is supported
    app["is_supported"] = is_app_supported(app)
    app["not_supported_reason"] = get_app_not_supported_reason(app)

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

    # Load dynamic app JSON files
    dynamic_app_dir = get_dynamic_app_dir()
    dynamic_app_names = get_dynamic_app_names()
    for app_name in dynamic_app_names:
        try:
            app_dir = dynamic_app_dir + "/" + app_name
            with open(app_dir + "/" + app_name + ".json", 'r') as app_info_file:
                app = json.load(app_info_file)
                apps.append(initialize_application_defaults(app))

        except Exception as e:
            log_message("ERROR: Could not initialize dynamic app {} - {}".format(app_name, str(e)))
            app = {"name":"???", "short_name": app_name, "error": "APP INIT EXCEPTION: {}".format(str(e))}
            apps.append( initialize_application_defaults( app ) )

    mynode_applications = copy.deepcopy(apps)
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


######################################################################################
## Get Applications and App Info
######################################################################################
def get_all_applications(order_by="none", include_status=False):
    global mynode_applications

    if need_application_refresh():
        clear_service_enabled_cache()
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

    # Filter data not necessary for cache
    for app in apps:
        app["description"] = ""
        app["app_page_content"] = ""

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
        elif short_name == "joinmarket-api":
            return get_journalctl_log("joinmarket-api")
        elif short_name == "www":
            return get_journalctl_log("www")
        elif short_name == "rathole":
            return get_journalctl_log("rathole")
        elif short_name == "premium_plus_connect":
            return get_journalctl_log("premium_plus_connect")
        elif short_name == "i2pd":
            return get_file_log("/var/log/i2pd/i2pd.log")
        elif short_name == "linux":
            return run_linux_cmd("dmesg | tac | head -n 200")
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
        if not is_dojo_initialized():
            return "Error Starting"
        tracker_status, tracker_status_text = get_dojo_tracker_status()
        dojo_status_code = get_service_status_code("dojo")
        if dojo_status_code != 0:
            return "Error"
        if tracker_status == TrackerStatus.SYNCING:
            return "Syncing..."
        elif tracker_status == TrackerStatus.ERROR:
            return "Tracker Error"
    elif short_name == "jam":
        if not is_installed("joininbox"):
            return "Requires JoinMarket"

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
        return to_string(app["short_description"])
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
    elif short_name == "jam":
        if not is_installed("joininbox"):
            return "yellow"
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


######################################################################################
## Legacy Custom App Versions
######################################################################################
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
## Custom App Versions
######################################################################################
def has_custom_app_version(short_name):
    if os.path.isfile("/home/bitcoin/.mynode/"+short_name+"_version_latest_custom"):
        return True
    if os.path.isfile("/mnt/hdd/mynode/settings/"+short_name+"_version_latest_custom"):
        return True
    return False

def save_custom_app_version(short_name, version):
    set_file_contents("/home/bitcoin/.mynode/"+short_name+"_version_latest_custom", version)
    set_file_contents("/mnt/hdd/mynode/settings/"+short_name+"_version_latest_custom", version)
    os.system("sync")
    trigger_application_refresh()

def clear_custom_app_version(short_name):
    os.system("rm -f /home/bitcoin/.mynode/"+short_name+"_version_latest_custom")
    os.system("rm -f /mnt/hdd/mynode/settings/"+short_name+"_version_latest_custom")
    os.system("sync")
    trigger_application_refresh()


######################################################################################
## Single Application Actions
######################################################################################
def create_application_user(app_data):
    #log_message("  Running create_application_user...")
    username = app_data["linux_user"]
    if not linux_user_exists(username):
        linux_create_user(username)
    
    # Ensure user belongs to bitcoin group
    add_user_to_group(username, "bitcoin")

    # If docker app, add them to docker
    if app_data["requires_docker_image_installation"]:
        add_user_to_group(username, "docker")

def create_application_folders(app_data):
    log_message("  Running create_application_folders...")
    app_folder = app_data["install_folder"]
    data_folder = app_data["storage_folder"]

    # Clear old data (not storage)
    if os.path.isdir(app_folder):
        log_message("  App folder exists, deleting...")
        run_linux_cmd("rm -rf {}".format(app_folder))

    log_message("  Making application folders...")
    run_linux_cmd("mkdir {}".format(app_folder))
    run_linux_cmd("mkdir -p {}".format(data_folder))

    # Set folder permissions (always set for now - could check to see if already proper user)
    log_message("  Updating folder permissions...")
    run_linux_cmd("chown -R {}:{} {}".format(app_data["linux_user"], app_data["linux_user"], app_folder))
    run_linux_cmd("chown -R {}:{} {}".format(app_data["linux_user"], app_data["linux_user"], data_folder))

def create_application_tor_service(app_data):
    has_ports = False
    run_linux_cmd("mkdir -p /etc/torrc.d")
    torrc_file = "/etc/torrc.d/"+app_data["short_name"]
    contents = "# Hidden Service for {}\n".format(app_data["short_name"])
    contents += "HiddenServiceDir /var/lib/tor/mynode_{}/\n".format(app_data["short_name"])
    if "http_port" in app_data and app_data["http_port"] != None:
        contents += "HiddenServicePort 80 127.0.0.1:{}\n".format(app_data["http_port"])
        has_ports = True
    if "https_port" in app_data and app_data["https_port"] != None:
        contents += "HiddenServicePort 443 127.0.0.1:{}\n".format(app_data["https_port"])
        has_ports = True
    if "extra_ports" in app_data and app_data["extra_ports"] != None:
        for p in app_data["extra_ports"]:
            contents += "HiddenServicePort {} 127.0.0.1:{}\n".format(p, p)
            has_ports = True

    if has_ports:
        with open(torrc_file, "w") as f:
            f.write(contents)

def install_application_tarball(app_data):
    log_message("  Running install_application_tarball...")

    ignore_failure = True

    # Make tmp download folder
    run_linux_cmd("rm -rf /tmp/mynode_dynamic_app_download", ignore_failure)
    run_linux_cmd("mkdir /tmp/mynode_dynamic_app_download")
    run_linux_cmd("chmod -R 777 /tmp/mynode_dynamic_app_download")
    run_linux_cmd("rm -rf /tmp/mynode_dynamic_app_extract", ignore_failure)
    run_linux_cmd("mkdir /tmp/mynode_dynamic_app_extract")
    run_linux_cmd("chmod -R 777 /tmp/mynode_dynamic_app_extract")

    # Download and extract
    if not app_data["download_skip"]:
        download_url = "not_specified"
        if app_data["download_type"] == "source" and app_data["download_source_url"] == None:
            log_message("  APP MISSING SOURCE DOWNLOAD URL")
            raise ValueError("APP MISSING SOURCE DOWNLOAD URL")
        if app_data["download_type"] == "binary" and app_data["download_binary_url"] == None:
            log_message("  APP MISSING BINARY DOWNLOAD URL")
            raise ValueError("APP MISSING BINARY DOWNLOAD URL")

        if app_data["download_type"] == "source":
            download_url = app_data["download_source_url"]
        elif app_data["download_type"] == "binary":
            found = False
            for arch in app_data["download_binary_url"]:
                if arch == get_device_arch():
                    download_url = app_data["download_binary_url"][arch]
                    found = True
            if not found:
                log_message("  CANNOT FIND BINARY URL FOR APP: {} CURRENT ARCH: {}".format(app_data["short_name"], get_device_arch()))
        else:
            log_message("  UNKNOWN download_type {}".format(app_data["download_type"]))
            raise ValueError("  UNKNOWN download_type {}".format(app_data["download_type"]))
        run_linux_cmd("wget -O /tmp/mynode_dynamic_app_download/app.tar.gz {}".format(download_url))

        time.sleep(1)
        run_linux_cmd("sync")
        run_linux_cmd("sudo -u {} tar -xvf /tmp/mynode_dynamic_app_download/app.tar.gz -C /tmp/mynode_dynamic_app_extract/".format(app_data["linux_user"]))
        run_linux_cmd("mv /tmp/mynode_dynamic_app_extract/* /tmp/mynode_dynamic_app_extract/app")

        # Move tarball contents to app folder
        run_linux_cmd("rsync -var --delete-after /tmp/mynode_dynamic_app_extract/app/ {}/".format(app_data["install_folder"]))

    # Move additional app data to app installation folder
    app_data_source = get_dynamic_app_dir() + "/" + app_data["short_name"] + "/app_data"
    app_data_dest = app_data["install_folder"] + "/app_data"
    run_linux_cmd("rm -rf {}".format(app_data_dest))
    if os.path.isdir(app_data_source):
        run_linux_cmd("cp -r -f {} {}".format(app_data_source, app_data_dest))
        run_linux_cmd("chown -R {}:{} {}".format(app_data["linux_user"],app_data["linux_user"],app_data_dest))

def clear_installed_version(short_name):
    run_linux_cmd("rm -rf /home/bitcoin/.mynode/{}_version".format(short_name))
    run_linux_cmd("rm -rf /mnt/hdd/mynode/settings/{}_version".format(short_name))

def restart_application(short_name):
    try:
        subprocess.check_output('systemctl restart {}'.format(short_name), shell=True)
        return True
    except Exception as e:
        return False

######################################################################################
## Bulk Application Actions
######################################################################################
def open_application_ports():
    print("Running open_application_ports...")
    trigger_application_refresh()
    apps = get_all_applications()
    for app in apps:
        try:
            print("Checking ports for {}".format(app["short_name"]))
            if "http_port" in app and app["http_port"] != None:
                print("  Opening HTTP {}".format(app["http_port"]))
                os.system("ufw allow {}  comment 'allow {} HTTP'".format(app["http_port"], app["short_name"]))
            if "https_port" in app and app["https_port"] != None:
                print("  Opening HTTPS {}".format(app["https_port"]))
                os.system("ufw allow {}  comment 'allow {} HTTPS'".format(app["https_port"], app["short_name"]))
            if "extra_ports" in app and app["extra_ports"] != None:
                for port in app["extra_ports"]:
                    print("  Opening Extra Port {}".format(port))
                    os.system("ufw allow {}  comment 'allow {} (extra)'".format(port, app["short_name"]))
        except Exception as e:
            log_message("ERROR: Error opening port for application {} - {}".format(app["short_name"], str(e))) 
    return None

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

def register_dynamic_app_flask_blueprints(flask_app):
    try:
        app_names = get_dynamic_app_names()
        for app_name in app_names:
            if os.path.isfile("/var/www/mynode/app/{}/{}.py".format(app_name, app_name)):
                log_message("Registering Flask Blueprint for {}".format(app_name))
                try:
                    mynode_app = getattr(importlib.import_module("app.{}.{}".format(app_name, app_name)), "mynode_{}".format(app_name))
                    flask_app.register_blueprint(mynode_app, url_prefix="/app/{}".format(app_name))
                except Exception as e:
                    log_message("register_dynamic_app_flask_blueprints import error - ({})".format(str(e)))
    except Exception as e:
        log_message("register_dynamic_app_flask_blueprints error - ({})".format(str(e)))

def init_dynamic_app(app_info):
    app_name = app_info["short_name"]
    app_dir = DYNAMIC_APPLICATIONS_FOLDER + "/" + app_name
    log_message(" Loading " + app_name + "...")
    # Create user if necessary
    create_application_user(app_info)
    # Install Service File (if exists)
    if (os.path.isfile(app_dir+"/"+app_name+".service")):
        os.system("cp -f {} {}".format(app_dir+"/"+app_name+".service", "/etc/systemd/system/"+app_name+".service"))
    # Install App Icon
    os.system("cp -f {} {}".format(app_dir+"/"+app_name+".png", "/var/www/mynode/static/images/app_icons/"+app_name+".png"))
    # Install Screenshots
    os.system("rm -rf /var/www/mynode/static/images/screenshots/{}".format(app_name))
    os.system("mkdir -p /var/www/mynode/static/images/screenshots/{}".format(app_name))
    if os.path.isdir(app_dir+"/screenshots/"):
        for s in os.listdir(app_dir+"/screenshots/"):
            if s.endswith(".png"):
                src=app_dir+"/screenshots/{}".format(s)
                dst="/var/www/mynode/static/images/screenshots/{}/{}".format(app_name, s)
                os.system("cp -f {} {}".format(src, dst))
    # Install scripts (pre, post, install, uninstall)
    if (os.path.isfile(app_dir+"/scripts/pre_"+app_name+".sh")):
        os.system("cp -f {} {}".format(app_dir+"/scripts/pre_"+app_name+".sh",      "/usr/bin/service_scripts/pre_"+app_name+".sh"))
    if (os.path.isfile(app_dir+"/scripts/post_"+app_name+".sh")):
        os.system("cp -f {} {}".format(app_dir+"/scripts/post_"+app_name+".sh",     "/usr/bin/service_scripts/post_"+app_name+".sh"))
    if (os.path.isfile(app_dir+"/scripts/install_"+app_name+".sh")):
        os.system("cp -f {} {}".format(app_dir+"/scripts/install_"+app_name+".sh",  "/usr/bin/service_scripts/install_"+app_name+".sh"))
    if (os.path.isfile(app_dir+"/scripts/uninstall_"+app_name+".sh")):
        os.system("cp -f {} {}".format(app_dir+"/scripts/uninstall_"+app_name+".sh", "/usr/bin/service_scripts/uninstall_"+app_name+".sh"))
    # Install NGINX config
    if (os.path.isfile(app_dir+"/nginx/https_"+app_name+".conf")):
        os.system("cp -f {} {}".format(app_dir+"/nginx/https_"+app_name+".conf", "/etc/nginx/sites-enabled/https_"+app_name+".conf"))

    # Install python web files (one with <short_name>.py is required)
    os.system("mkdir -p /var/www/mynode/app/{}/".format(app_name))
    for filename in os.listdir(app_dir+"/www/python"):
        if filename.endswith(".py"):
            src = app_dir+"/www/python/"+filename
            dst = "/var/www/mynode/app/"+app_name+"/"+filename
            os.system("cp -f {} {}".format(src, dst))
    os.system("mkdir -p /var/www/mynode/templates/app/{}/".format(app_name))
    # Install template web files
    for filename in os.listdir(app_dir+"/www/templates"):
        if filename.endswith(".html"):
            src = app_dir+"/www/templates/"+filename
            dst = "/var/www/mynode/templates/app/"+app_name+"/"+filename
            os.system("cp -f {} {}".format(src, dst))

    # For "node" type apps
    #log_message("  TODO: Need node special files???")

    # For "python" type apps
    #log_message("  TODO: Need python special files???")

    # For "docker" type apps
    #log_message("  TODO: Build dockerfile???")
    #log_message("  TODO: Install dockerfile???")

    # Move update app_data files of dynamic apps that have been installed
    app_data_source = app_dir + "/app_data"
    app_data_dest = app_info["install_folder"] + "/app_data"
    if os.path.isdir(app_data_dest):
        run_linux_cmd("rm -rf {}".format(app_data_dest))
        if os.path.isdir(app_data_source):
            run_linux_cmd("cp -r -f {} {}".format(app_data_source, app_data_dest))
            run_linux_cmd("chown -R {}:{} {}".format(app_info["linux_user"],app_info["linux_user"],app_data_dest))

    # Setup tor hidden service
    create_application_tor_service(app_info)

    log_message(" Done.")

def init_dynamic_apps(short_name="all"):
    # Ensure external drive is mounted
    if not is_mynode_drive_mounted():
        log_message("  ERROR: Data drive not mounted. Cannot Init Dynamic Apps.")
        return
    
    # Loop over each app
    root_app_dir = get_dynamic_app_dir()
    app_names = get_dynamic_app_names()
    for app_name in app_names:
        if short_name == "all" or short_name == app_name:
            log_message("Found Application: {}".format(app_name))
            app_dir = root_app_dir + "/" + app_name
            try:
                app_json_path = app_dir + "/{}.json".format(app_name)
                with open(app_json_path, 'r') as fp:
                    app_info = json.load(fp)
                    app_info = initialize_application_defaults(app_info)
                    init_dynamic_app(app_info)

            except Exception as e:
                log_message("  ERROR: Error loading {}.json file ({})".format(app_name, str(e)))

    # Reload systemctl files
    os.system("systemctl daemon-reload")

    # Mark app db for needing reload
    clear_application_cache()

def upgrade_dynamic_apps(short_name="all"):
    log_message("Running upgrade_dynamic_apps...")

    if short_name != "all" and not is_application_valid(short_name):
        print("  Invalid app: {}".format(short_name))
        return

    # Loop over each app
    app_names = get_dynamic_app_names()
    for app_name in app_names:
        if short_name == "all" or short_name == app_name:
            try:
                # Get app and make sure app info is updated (otherwise installed marker may be wrong)
                app_data = get_application( app_name )
                app_data = initialize_application_defaults(app_data)

                if app_data["is_installed"]:
                    #log_message("{} vs {}".format(app_data["current_version"], app_data["latest_version"]))

                    if app_data["current_version"] != app_data["latest_version"]:
                        log_message("  Upgrading {} ({} vs {})...".format(app_name, app_data["current_version"], app_data["latest_version"]))
                        try:
                            # Make app linux user
                            create_application_user(app_data)

                            # Does any app user need extra groups/permissions
                            # ???

                            # Clear old data, make app folder, make storage folder, and set folder ownership
                            create_application_folders(app_data)
                            
                            # Download tarball, extract into install folder
                            install_application_tarball(app_data)

                            # Run upgrade script (redirect to err so output is visible on console / print)
                            my_env = os.environ.copy()
                            my_env["VERSION"] = app_data["latest_version"]
                            my_env["INSTALL_FOLDER"] = app_data["install_folder"]
                            my_env["STORAGE_FOLDER"] = app_data["storage_folder"]
                            if app_data["install_env_vars"]:
                                for key in app_data["install_env_vars"]:
                                    my_env[key] = app_data["install_env_vars"][key]
                            # Home dir needs to be set to user so it doesn't inhert root home (causes docker issues)
                            subprocess.check_output("cd {}; sudo -u {} --preserve-env HOME=/home/{} /bin/bash /usr/bin/service_scripts/install_{}.sh 1>&2".format(app_data["install_folder"], app_data["linux_user"], app_data["linux_user"], app_name), shell=True, env=my_env)

                            # Mark update latest version if success
                            log_message("  Upgrade success!")
                            set_file_contents("/home/bitcoin/.mynode/{}_version".format(app_name), app_data["latest_version"])
                        except Exception as e:
                            # Write error to version file
                            log_message("  Upgrade FAILED! ({})".format(str(e)))
                            set_file_contents("/home/bitcoin/.mynode/{}_version".format(app_name), "error")
            except Exception as e:
                log_message("  ERROR: Error checking app {} for upgrade ({})".format(app_name, str(e)))

def list_dynamic_apps():
    app_names = get_dynamic_app_names()
    print("Dynamic Apps")
    for app_name in app_names:
        print("  {}".format(app_name))

def stop_dynamic_apps(app_names):
    dynamic_app_names = get_dynamic_app_names()
    for app_name in app_names:
        for dynamic_app_name in dynamic_app_names:
            if app_name == "all" or app_name == dynamic_app_name:
                app_data = get_application( dynamic_app_name )
                if app_data["can_enable_disable"]:
                    stop_service(dynamic_app_name)


# Typically, the mynode_uninstall_app.sh runs first and calls mynode-manage-apps uninstall to run this
#   Prior to running, service should have been stopped and disabled
#   Post running, the app install folder will be deleted (not the storage folder on data drive)
# HOWEVER! To make sure running this alone works if managing apps via the CLI, those actions are repeated
def uninstall_dynamic_app(short_name):
    print("Uninstalling app {}...".format(short_name))

    app_data = get_application(short_name)
    if app_data == None:
        print(" Invalid app: {}".format(short_name))
        exit(1)

    # Run app-specific uninstall script
    uninstall_script = "/usr/bin/service_scripts/uninstall_{}.sh".format(short_name)
    if os.path.isfile(uninstall_script):
        try:
            my_env = os.environ.copy()
            my_env["VERSION"] = app_data["latest_version"]
            my_env["INSTALL_FOLDER"] = app_data["install_folder"]
            my_env["STORAGE_FOLDER"] = app_data["storage_folder"]
            if app_data["install_env_vars"]:
                for key in app_data["install_env_vars"]:
                    my_env[key] = app_data["install_env_vars"][key]
            subprocess.check_output("cd {}; sudo -u {} /bin/bash /usr/bin/service_scripts/uninstall_{}.sh 1>&2".format(app_data["install_folder"], app_data["linux_user"], short_name), shell=True, env=my_env)
        except Exception as e:
            print("  Exception: {}".format(str(e)))
    
    # Delete install marker files
    clear_app_installed(short_name)

    # Disable service 
    disable_service(short_name)

    # Delete SD card folder
    run_linux_cmd("rm -rf {}".format(app_data["install_folder"]))

    # Clear app data
    clear_application_cache()
