from config import *
from threading import Timer
from werkzeug.routing import RequestRedirect
from flask import flash, redirect
from utilities import *
from enable_disable_functions import *
from systemctl_info import *
import time
import json
import os
import subprocess
import random
import string
import re
import psutil

try:
    import qrcode
except:
    pass
try:
    import subprocess32
except:
    pass

# Globals
local_ip = "unknown"
cached_data = {}
warning_data = {}
ui_settings = None

#==================================
# Manage Device
#==================================
def reboot_device():
    os.system("sync")
    os.system("/usr/bin/mynode_stop_critical_services.sh")
    os.system("reboot")

def shutdown_device():
    os.system("sync")
    os.system("/usr/bin/mynode_stop_critical_services.sh")
    os.system("shutdown -h now")

def is_shutting_down():
    return os.path.isfile("/tmp/shutting_down")

def factory_reset():
    # Try and make sure drive is r/w
    os.system("mount -o remount,rw /mnt/hdd")

    # Reset subsystems that have local data
    delete_quicksync_data()

    # Delete LND data
    delete_lnd_data()

    # Delete Tor data
    reset_tor()

    # Disable services
    os.system("systemctl disable electrs --no-pager")
    os.system("systemctl disable lndhub --no-pager")
    os.system("systemctl disable btcrpcexplorer --no-pager")
    os.system("systemctl disable vpn --no-pager")

    # Trigger drive to be reformatted on reboot
    os.system("rm -f /mnt/hdd/.mynode")

    # Delete settings files on SD card
    os.system("rm -f /home/bitcoin/.mynode/.btc_lnd_tor_enabled_defaulted")
    os.system("rm -f /home/bitcoin/.mynode/.product_key")
    os.system("rm -f /home/bitcoin/.mynode/ui.json")

    # Reset password
    os.system("/usr/bin/mynode_chpasswd.sh bolt")

    # Reboot
    reboot_device()

def check_and_mark_reboot_action(tmp_marker):
    tmp_marker_file = "/tmp/mark_reboot___{}".format(tmp_marker)
    if os.path.isfile(tmp_marker_file):
        flash(u'Refresh prevented - action already triggered', category="error")
        raise RequestRedirect("/")
    touch(tmp_marker_file)

def reload_throttled_data():
    global cached_data
    if os.path.isfile("/tmp/get_throttled_data"):
        cached_data["get_throttled_data"] = to_string( get_file_contents("/tmp/get_throttled_data") )

def get_throttled_data():
    global cached_data
    if "get_throttled_data" in cached_data:
        data = cached_data["get_throttled_data"]
        hex_data = int(data, 16)
        r = {}
        r["RAW_DATA"] = data
        r["UNDERVOLTED"] = 1 if hex_data & 0x1 else 0
        r["CAPPED"] = 1 if hex_data & 0x2 else 0
        r["THROTTLED"] = 1 if hex_data & 0x4 else 0
        r["SOFT_TEMPLIMIT"] = 1 if hex_data & 0x8 else 0
        r["HAS_UNDERVOLTED"] = 1 if hex_data & 0x10000 else 0
        r["HAS_CAPPED"] = 1 if hex_data & 0x20000 else 0
        r["HAS_THROTTLED"] = 1 if hex_data & 0x40000 else 0
        r["HAS_SOFT_TEMPLIMIT"] = 1 if hex_data & 0x80000 else 0
        return r
    else:
        r = {}
        r["RAW_DATA"] = "MISSING"
        return r

#==================================
# Manage Versions and Upgrades
#==================================
def get_current_version():
    current_version = "0.0"
    try:
        with open("/usr/share/mynode/version", "r") as f:
            current_version = f.read().strip()
    except:
        current_version = "error"
    return current_version

def get_current_beta_version():
    current_beta_version = "0.0"
    try:
        with open("/usr/share/mynode/beta_version", "r") as f:
            current_beta_version = f.read().strip()
    except:
        current_beta_version = "beta_not_installed"
    return current_beta_version

def update_latest_version():
    os.system("/usr/bin/mynode_get_latest_version.sh")
    return True

def get_latest_version():
    latest_version = "0.0"
    try:
        with open("/usr/share/mynode/latest_version", "r") as f:
            latest_version = f.read().strip()
            if latest_version == "":
                latest_version = get_current_version()
    except:
        latest_version = get_current_version()
    return latest_version

def get_latest_beta_version():
    beta_version = ""
    try:
        with open("/usr/share/mynode/latest_beta_version", "r") as f:
            beta_version = f.read().strip()
    except:
        beta_version = ""
    return beta_version

def mark_upgrade_started():
    touch("/tmp/upgrade_started")

def is_upgrade_running():
    return os.path.isfile("/tmp/upgrade_started") 

def upgrade_device():
    if not is_upgrade_running():
        mark_upgrade_started()

        # Upgrade
        os.system("mkdir -p /home/admin/upgrade_logs")
        os.system("cp -f /usr/bin/mynode_upgrade.sh /usr/bin/mynode_upgrade_running.sh")
        file1 = "/home/admin/upgrade_logs/upgrade_log_from_{}_upgrade.txt".format(get_current_version())
        file2 = "/home/admin/upgrade_logs/upgrade_log_latest.txt"
        cmd = "/usr/bin/mynode_upgrade_running.sh 2>&1 | tee {} {}".format(file1, file2)
        ret = subprocess.call(cmd, shell=True)
        if ret != 0:
            # Try one more time....
            subprocess.call(cmd, shell=True)
        
        # Sync
        os.system("sync")
        time.sleep(1)

        # Reboot
        reboot_device()

def upgrade_device_beta():
    if not is_upgrade_running():
        mark_upgrade_started()

        # Upgrade
        os.system("mkdir -p /home/admin/upgrade_logs")
        os.system("cp -f /usr/bin/mynode_upgrade.sh /usr/bin/mynode_upgrade_running.sh")
        file1 = "/home/admin/upgrade_logs/upgrade_log_from_{}_upgrade.txt".format(get_current_version())
        file2 = "/home/admin/upgrade_logs/upgrade_log_latest.txt"
        cmd = "/usr/bin/mynode_upgrade_running.sh beta 2>&1 | tee {} {}".format(file1, file2)
        ret = subprocess.call(cmd, shell=True)
        if ret != 0:
            # Try one more time....
            subprocess.call(cmd, shell=True)
        
        # Sync
        os.system("sync")
        time.sleep(1)

        # Reboot
        reboot_device()

def did_upgrade_fail():
    return os.path.isfile("/mnt/hdd/mynode/settings/upgrade_error")

def cleanup_log(log):
    log = re.sub("(product_key|PRODUCT_KEY)=[0-9A-Z]+", "product_key=************", log)
    return log

def get_recent_upgrade_log():
    log =  to_string( get_file_contents("/home/admin/upgrade_logs/upgrade_log_latest.txt") )
    return cleanup_log(log)

def get_all_upgrade_logs():
    log_list = []
    folder = "/home/admin/upgrade_logs/"
    log_id = 0

    try:
        # Add latest upgrade log
        if os.path.isfile( os.path.join(folder, "upgrade_log_latest.txt") ):
            log = {}
            log["id"] = log_id
            log["name"] = "Latest Upgrade"
            modTimeSeconds = os.path.getmtime( os.path.join(folder, "upgrade_log_latest.txt") )
            log["date"] = time.strftime('%Y-%m-%d', time.localtime(modTimeSeconds))
            log["log"] = get_recent_upgrade_log()
            log_list.append( log )
            log_id += 1

        # Add file logs
        if os.path.isdir(folder):
            for f in os.listdir(folder):
                fullpath = os.path.join(folder, f)
                if os.path.isfile( fullpath ):
                    log = {}
                    log["id"] = log_id
                    log["name"] = f
                    modTimeSeconds = os.path.getmtime(fullpath)
                    log["date"] = time.strftime('%Y-%m-%d', time.localtime(modTimeSeconds))
                    log["log"] = cleanup_log( to_string( get_file_contents(fullpath) ) )
                    log_list.append( log )
                    log_id += 1
    except Exception as e:
        pass

    return log_list

def has_checkin_error():
    return os.path.isfile("/tmp/check_in_error")


#==================================
# Reseller Info
#==================================
def is_device_from_reseller():
    return os.path.isfile("/opt/mynode/custom/reseller")


#==================================
# Device Info
#==================================
def get_system_uptime():
    uptime = to_string(subprocess.check_output('awk \'{print int($1/86400)" days "int($1%86400/3600)" hour(s) "int(($1%3600)/60)" minute(s)"}\' /proc/uptime', shell=True))
    uptime = uptime.strip()
    return uptime

def get_system_uptime_in_seconds():
    uptime = to_string(subprocess.check_output('awk \'{print $1}\' /proc/uptime', shell=True))
    uptime = int(float(uptime.strip()))
    return uptime

def get_system_time_in_ms():
    return int(round(time.time() * 1000))

def get_system_date():
    date = to_string(subprocess.check_output('date', shell=True))
    date = date.strip()
    return date

def get_device_serial():
    global cached_data
    if "serial" in cached_data:
        return cached_data["serial"]

    serial = to_string(subprocess.check_output("mynode-get-device-serial", shell=True))
    serial = serial.strip()

    cached_data["serial"] = serial
    return serial

def get_device_type():
    global cached_data
    if "device_type" in cached_data:
        return cached_data["device_type"]
    
    device = to_string(subprocess.check_output("mynode-get-device-type", shell=True).strip())
    cached_data["device_type"] = device
    return device

def get_device_arch():
    global cached_data
    if "device_arch" in cached_data:
        return cached_data["device_arch"]

    arch = to_string(subprocess.check_output("uname -m", shell=True).decode("utf-8").strip())
    cached_data["device_arch"] = arch
    return arch

def get_debian_version():
    global cached_data
    if "debian_version" in cached_data:
        return cached_data["debian_version"]

    debian_version = to_string(subprocess.check_output("lsb_release -c -s", shell=True).decode("utf-8").strip())
    cached_data["debian_version"] = debian_version
    return debian_version

def get_device_ram():
    global cached_data
    if "ram" in cached_data:
        return cached_data["ram"]

    ram = to_string(subprocess.check_output("free --giga | grep Mem | awk '{print $2}'", shell=True).strip())
    cached_data["ram"] = ram
    return ram

def get_device_temp():
    if is_cached("device_temp", 60):
        return get_cached_data("device_temp")

    device_temp = "..."
    try:
        results = to_string(subprocess.check_output("cat /sys/class/thermal/thermal_zone0/temp", shell=True))
        temp = int(results) / 1000
        device_temp = "{:.1f}".format(temp)
        update_cached_data("device_temp", device_temp)
    except:
        return device_temp
    return device_temp

def get_ram_usage():
    if is_cached("ram_usage", 120):
        return get_cached_data("ram_usage")

    ram_usage = "..."
    try:
        ram_info = psutil.virtual_memory()
        ram_usage = "{:.1f}%".format(ram_info.percent)
    except:
        return ram_usage
    return ram_usage
    
def get_swap_usage():
    if is_cached("swap_usage", 120):
        return get_cached_data("swap_usage")

    swap_usage = "..."
    try:
        swap_info = psutil.swap_memory()
        swap_usage = "{:.1f}%".format(swap_info.percent)
    except:
        return swap_usage
    return swap_usage

def get_local_ip():
    local_ip = "unknown"
    try:
        local_ip = to_string(subprocess.check_output('/usr/bin/get_local_ip.py', shell=True).strip())
    except:
        local_ip = "error"

    return local_ip

def get_local_ip_subnet_conflict():
    ip = get_local_ip()
    if ip.startswith("172."):
        return True
    return False

def get_device_changelog():
    changelog = ""
    try:
        changelog = to_string(subprocess.check_output(["cat", "/usr/share/mynode/changelog"]))
    except:
        changelog = "ERROR"
    return changelog

def has_changed_password():
    try:
        with open("/home/bitcoin/.mynode/.hashedpw", "r") as f:
            hashedpw = f.read().strip()
            if hashedpw != "d0b3cba71f725563d316ea3516099328042095d10f4571be25c07f9ce31985a5":
                return True
    except:
        return False
    return False

def hide_password_warning():
    if os.path.isfile("/mnt/hdd/mynode/settings/hide_password_warning"):
        return True
    return False

def is_mount_read_only(mnt):
    with open('/proc/mounts') as f:
        for line in f:
            device, mount_point, filesystem, flags, __, __ = line.split()
            flags = flags.split(',')
            if mount_point == mnt:
                return 'ro' in flags
    return False

def set_swap_size(size):
    size_mb = int(size) * 1024
    os.system("sed -i 's|CONF_SWAPSIZE=.*|CONF_SWAPSIZE={}|' /etc/dphys-swapfile".format(size_mb))
    return set_file_contents("/mnt/hdd/mynode/settings/swap_size", size)

def get_swap_size():
    return to_string( get_file_contents("/mnt/hdd/mynode/settings/swap_size") )

#==================================
# myNode Status
#==================================
STATE_DRIVE_MISSING =         "drive_missing"
STATE_DRIVE_CONFIRM_FORMAT =  "drive_format_confirm"
STATE_DRIVE_FORMATTING =      "drive_formatting"
STATE_DRIVE_MOUNTED =         "drive_mounted"
STATE_DRIVE_CLONE =           "drive_clone"
STATE_DRIVE_FULL =            "drive_full"
STATE_DOCKER_RESET =          "docker_reset"
STATE_GEN_DHPARAM =           "gen_dhparam"
STATE_QUICKSYNC_DOWNLOAD =    "quicksync_download"
STATE_QUICKSYNC_COPY =        "quicksync_copy"
STATE_QUICKSYNC_RESET =       "quicksync_reset"
STATE_STABLE =                "stable"
STATE_ROOTFS_READ_ONLY =      "rootfs_read_only"
STATE_HDD_READ_ONLY =         "hdd_read_only"
STATE_SHUTTING_DOWN =         "shutting_down"
STATE_UPGRADING =             "upgrading"
STATE_UNKNOWN =               "unknown"

def get_mynode_status():
    try:
        status_file = "/tmp/.mynode_status"
        status = STATE_UNKNOWN

        # Get status
        if (os.path.isfile(status_file)):
            try:
                with open(status_file, "r") as f:
                    status = f.read().strip()
            except:
                status = STATE_DRIVE_MISSING
        else:
            status = STATE_DRIVE_MISSING

        # If its been a while, check for error conditions
        uptime_in_sec = get_system_uptime_in_seconds()
        if uptime_in_sec > 120:
            # Check for read-only sd card
            if is_mount_read_only("/"):
                return STATE_ROOTFS_READ_ONLY
            # Check for read-only drive (unless cloning - it purposefully mounts read only)
            if is_mount_read_only("/mnt/hdd") and status != STATE_DRIVE_CLONE:
                return STATE_HDD_READ_ONLY
    except:
        status = STATE_UNKNOWN
    return status

#==================================
# myNode Clone Tool
#==================================
CLONE_STATE_DETECTING       = "detecting"
CLONE_STATE_ERROR           = "error"
CLONE_STATE_NEED_CONFIRM    = "need_confirm"
CLONE_STATE_IN_PROGRESS     = "in_progress"
CLONE_STATE_COMPLETE        = "complete"

def get_clone_state():
    return to_string( get_file_contents("/tmp/.clone_state") )

def get_clone_error():
    return to_string( get_file_contents("/tmp/.clone_error") )

def get_clone_progress():
    return to_string( get_file_contents("/tmp/.clone_progress") )

def get_clone_source_drive():
    return to_string( get_file_contents("/tmp/.clone_source") )

def get_clone_target_drive():
    return to_string( get_file_contents("/tmp/.clone_target") )

def get_clone_target_drive_has_mynode():
    return os.path.isfile("/tmp/.clone_target_drive_has_mynode")

def get_drive_info(drive):
    data = {}
    data["name"] = "NOT_FOUND"
    try:
        lsblk_output = to_string(subprocess.check_output("lsblk -io KNAME,TYPE,SIZE,MODEL,VENDOR /dev/{} | grep disk".format(drive), shell=True).decode("utf-8"))
        parts = lsblk_output.split()
        data["name"] = parts[0]
        data["size"] = parts[2]
        data["model"] = parts[3]
        data["vendor"] = parts[4]
    except:
        pass
    return data


#==================================
# UI Functions
#==================================
def init_ui_setting_defaults(ui_settings):
    if "darkmode" not in ui_settings:
        ui_settings["darkmode"] = False
    if "price_ticker" not in ui_settings:
        ui_settings["price_ticker"] = False
    if "pinned_lightning_details" not in ui_settings:
        ui_settings["pinned_lightning_details"] = False
    if "background" not in ui_settings:
        ui_settings["background"] = "none"
    return ui_settings

def read_ui_settings():
    global ui_settings
    if ui_settings != None:
        return ui_settings
    
    ui_hdd_file = '/mnt/hdd/mynode/settings/ui.json'
    ui_mynode_file = '/home/bitcoin/.mynode/ui.json'

    # read ui.json from HDD
    try:
        if os.path.isfile(ui_hdd_file):
            with open(ui_hdd_file, 'r') as fp:
                ui_settings = json.load(fp)
        # read ui.json from mynode
        elif os.path.isfile(ui_mynode_file):
            with open(ui_mynode_file, 'r') as fp:
                ui_settings = json.load(fp)
    except Exception as e:
        # Error reading ui settings
        pass

    # If no files were read, init variable and mark we need to write files
    need_file_write = False
    if ui_settings == None:
        ui_settings = {}
        ui_settings["background"] = "digital"
        need_file_write = True

    # Set reseller
    ui_settings["reseller"] = is_device_from_reseller()

    # Load defaults
    ui_settings = init_ui_setting_defaults(ui_settings)

    if need_file_write:
        write_ui_settings(ui_settings)

    return ui_settings

def write_ui_settings(ui_settings_new):
    global ui_settings
    ui_settings = ui_settings_new

    ui_hdd_file = '/mnt/hdd/mynode/settings/ui.json'
    ui_mynode_file = '/home/bitcoin/.mynode/ui.json'
    try:
        with open(ui_hdd_file, 'w') as fp:
            json.dump(ui_settings, fp)

        with open(ui_mynode_file, 'w') as fp:
            json.dump(ui_settings, fp)
    except:
        pass

def get_ui_setting(name):
    ui_settings = read_ui_settings()
    return ui_settings[name]

def set_ui_setting(name, value):
    ui_settings = read_ui_settings()
    ui_settings[name] = value
    write_ui_settings(ui_settings)

def toggle_ui_setting(name):
    set_ui_setting(name, not get_ui_setting(name))


# def get_background_choices():
#     choices = []
#     choices.append("none")
#     for filename in os.listdir("/var/www/mynode/static/images/backgrounds/"):
#         if filename.endswith(".png") or filename.endswith(".jpg"):
#             name = filename.replace(".png","").replace(".jpg","")
#             choices.append(name)
#     return choices

def is_https_forced():
    return settings_file_exists("https_forced")

# Regen cert
def regen_https_cert():
    os.system("rm -rf /home/bitcoin/.mynode/https")
    os.system("rm -rf /mnt/hdd/mynode/settings/https")
    os.system("/usr/bin/mynode_gen_cert.sh https 825")
    os.system("sync")
    os.system("systemctl restart nginx")

def get_flask_secret_key():
    if os.path.isfile("/home/bitcoin/.mynode/flask_secret_key"):
        key = to_string( get_file_contents("/home/bitcoin/.mynode/flask_secret_key") )
    else:
        letters = string.ascii_letters
        key = ''.join(random.choice(letters) for i in range(32))
        set_file_contents("/home/bitcoin/.mynode/flask_secret_key", key)
    return key

def get_flask_session_timeout():
    try:
        if os.path.isfile("/home/bitcoin/.mynode/flask_session_timeout"):
            timeout = to_string( get_file_contents("/home/bitcoin/.mynode/flask_session_timeout") )
            parts = timeout.split(",")
            d = parts[0]
            h = parts[1]
            return int(d),int(h)
        else:
            set_file_contents("/home/bitcoin/.mynode/flask_session_timeout", "7,0")
            return 7,0
    except:
        return 7,0

def set_flask_session_timeout(days, hours):
    set_file_contents("/home/bitcoin/.mynode/flask_session_timeout", "{},{}".format(days, hours))
    os.system("sync")


#==================================
# Web Server Functions
#==================================
def restart_flask():
    os.system("systemctl restart www")


#==================================
# Uploader Functions
#==================================
def is_uploader():
    return os.path.isfile("/mnt/hdd/mynode/settings/uploader")
def set_uploader():
    touch("/mnt/hdd/mynode/settings/uploader")
def unset_uploader():
    delete_file("/mnt/hdd/mynode/settings/uploader")


#==================================
# QuickSync Functions
#==================================
def is_quicksync_enabled():
    return not os.path.isfile("/mnt/hdd/mynode/settings/quicksync_disabled")
def disable_quicksync():
    touch("/mnt/hdd/mynode/settings/quicksync_disabled")
def enable_quicksync():
    delete_file("/mnt/hdd/mynode/settings/quicksync_disabled")

def settings_disable_quicksync():
    disable_quicksync()
    stop_bitcoin()
    stop_quicksync()
    disable_quicksync() # Try disable again (some users had disable fail)
    delete_quicksync_data()
    reboot_device()

def settings_enable_quicksync():
    stop_bitcoin()
    stop_quicksync()
    enable_quicksync()
    delete_quicksync_data()
    reboot_device()

def delete_quicksync_data():
    os.system("rm -rf /mnt/hdd/mynode/quicksync")
    os.system("rm -rf /home/bitcoin/.config/transmission") # Old dir
    os.system("rm -rf /mnt/hdd/mynode/.config/transmission")

def stop_quicksync():
    os.system("systemctl stop quicksync")

def restart_quicksync():
    os.system('echo "quicksync_reset" > /tmp/.mynode_status')
    stop_bitcoin()
    stop_quicksync()
    delete_bitcoin_data()
    delete_quicksync_data()
    enable_quicksync()
    reboot_device()

def get_quicksync_log():
    log = "UNKNOWN"
    if is_quicksync_enabled():
        try:
            log = to_string(subprocess.check_output(["mynode-get-quicksync-status"]).decode("utf8"))
        except:
            log = "ERROR"
    else:
        log = "Disabled"
    return log


#==================================
# Product Key Functions
#==================================
def set_skipped_product_key():
    touch("/home/bitcoin/.mynode/.product_key_skipped")
    touch("/mnt/hdd/mynode/settings/.product_key_skipped")
def unset_skipped_product_key():
    delete_file("/home/bitcoin/.mynode/.product_key_skipped")
    delete_file("/mnt/hdd/mynode/settings/.product_key_skipped")
def skipped_product_key():
    return os.path.isfile("/home/bitcoin/.mynode/.product_key_skipped") or \
           os.path.isfile("/mnt/hdd/mynode/settings/.product_key_skipped")
def is_community_edition():
    return skipped_product_key()

def delete_product_key():
    delete_file("/home/bitcoin/.mynode/.product_key")
    delete_file("/mnt/hdd/mynode/settings/.product_key")
def has_product_key():
    return os.path.isfile("/home/bitcoin/.mynode/.product_key")
def get_product_key():
    product_key = "no_product_key"
    if skipped_product_key():
        return "community_edition"

    if not has_product_key():
        return "product_key_missing"

    try:
        with open("/home/bitcoin/.mynode/.product_key", "r") as f:
            product_key = f.read().strip()
    except:
        product_key = "product_key_error"
    return product_key
def is_valid_product_key():
    return not os.path.isfile("/home/bitcoin/.mynode/.product_key_error")
def save_product_key(product_key):
    pk = product_key.replace("-","")
    os.system("echo '{}' > /home/bitcoin/.mynode/.product_key".format(pk))
    os.system("echo '{}' > /mnt/hdd/mynode/settings/.product_key".format(pk))
def mark_product_key_error():
    os.system("echo '{}' > /home/bitcoin/.mynode/.product_key_error".format("ERROR"))
def delete_product_key_error():
    os.system("rm -rf /home/bitcoin/.mynode/.product_key_error")
    os.system("rm -rf /mnt/hdd/mynode/settings/.product_key_error")

def recheck_product_key():
    delete_product_key_error()
    restart_check_in()

#==================================
# Check In Functions
#==================================
def restart_check_in():
    os.system("systemctl restart check_in")

def get_check_in_data():
    data = []
    try:
        with open("/tmp/check_in_response.json", "r") as f:
            data = json.load(f)
    except Exception as e:
        data =  None
    return data

def dismiss_expiration_warning():
    touch("/tmp/dismiss_expiration_warning")

def is_expiration_warning_dismissed():
    return os.path.isfile("/tmp/dismiss_expiration_warning")

def is_support_near_expiration():
    data = get_check_in_data()
    if data != None and "support" in data:
        support = data["support"]
        if "days_remaining" in support:
            days_remaining = int(support["days_remaining"])
            if days_remaining >= -60 and days_remaining <= 45:
                return True
    return False

def is_premium_plus_near_expiration():
    data = get_check_in_data()
    if data != None and "premium_plus" in data:
        premium_plus = data["premium_plus"]
        if "days_remaining" in premium_plus:
            days_remaining = int(premium_plus["days_remaining"])
            if days_remaining >= -60 and days_remaining <= 45:
                return True
    return False

#==================================
# Premium+ Token Functions
#==================================
def delete_premium_plus_token():
    delete_file("/home/bitcoin/.mynode/.premium_plus_token")
    delete_file("/mnt/hdd/mynode/settings/.premium_plus_token")
def has_premium_plus_token():
    return os.path.isfile("/home/bitcoin/.mynode/.premium_plus_token") or \
           os.path.isfile("/mnt/hdd/mynode/settings/.premium_plus_token")
def get_premium_plus_token():
    token = "error_1"
    if not has_premium_plus_token():
        return ""

    try:
        if os.path.isfile("/home/bitcoin/.mynode/.premium_plus_token"):
            with open("/home/bitcoin/.mynode/.premium_plus_token", "r") as f:
                token = f.read().strip()
        elif os.path.isfile("/mnt/hdd/mynode/settings/.premium_plus_token"):
            with open("/mnt/hdd/mynode/settings/.premium_plus_token", "r") as f:
                token = f.read().strip()

                # Re-save to SD card since it was missing
                set_file_contents("/home/bitcoin/.mynode/.premium_plus_token", token)
    except:
        token = "error_2"
    return token
def reset_premium_plus_token_status():
    delete_file("/home/bitcoin/.mynode/.premium_plus_token_status")
def set_premium_plus_token_status(msg):
    os.system("echo '{}' > /home/bitcoin/.mynode/.premium_plus_token_status".format(msg))
def get_premium_plus_token_status():
    status = "UNKNOWN"
    if not has_premium_plus_token():
        return "No Token Set"
    if not os.path.isfile("/home/bitcoin/.mynode/.premium_plus_token_status"):
        return "Updating..."
    try:
        with open("/home/bitcoin/.mynode/.premium_plus_token_status", "r") as f:
            status = f.read().strip()
    except:
        status = "STATUS_ERROR_2"
    return status
def get_premium_plus_is_connected():
    status = get_premium_plus_token_status()
    if status == "OK":
        return True
    return False
def update_premium_plus_last_sync_time():
    t = int(round(time.time()))
    os.system("echo '{}' > /home/bitcoin/.mynode/.premium_plus_last_sync".format(t))
def get_premium_plus_last_sync():
    try:
        now = int(round(time.time()))
        last = int(get_file_contents("/home/bitcoin/.mynode/.premium_plus_last_sync"))
        diff_min = int((now - last) / 60)
        if diff_min == 0:
            return "Now"
        else:
            return "{} minutes(s) ago".format(diff_min)
    except Exception as e:
        return "Unknown"
def save_premium_plus_token(token):
    set_file_contents("/home/bitcoin/.mynode/.premium_plus_token", token)
    set_file_contents("/mnt/hdd/mynode/settings/.premium_plus_token", token)

def get_premium_plus_response_data():
    data = []
    try:
        with open("/tmp/premium_plus_response.json", "r") as f:
            data = json.load(f)
    except Exception as e:
        data = None
    return data

def recheck_premium_plus_token():
    reset_premium_plus_token_status()
    os.system("systemctl restart premium_plus_connect")

def get_premium_plus_setting_names():
    return ["sync_status","sync_bitcoin_and_lightning","backup_scb","watchtower"]
def get_premium_plus_settings():
    names = get_premium_plus_setting_names()
    settings = {}
    for n in names:
        settings[n] = False
    for n in names:
        settings[n] = settings_file_exists(n)
    return settings

#==================================
# Drive Repair Functions
#==================================
def is_drive_being_repaired():
    return os.path.isfile("/tmp/repairing_drive")
def has_fsck_error():
    return os.path.isfile("/tmp/fsck_error")
def clear_fsck_error():
    os.system("rm -f /tmp/fsck_error")
def get_fsck_results():
    try:
        with open("/tmp/fsck_results", "r") as f:
            return f.read()
    except:
        return "ERROR"
    return "ERROR"

def set_skip_fsck(skip):
    if skip:
        touch("/home/bitcoin/.mynode/skip_fsck")
    else:
        delete_file("/home/bitcoin/.mynode/skip_fsck")
def skip_fsck():
    return os.path.isfile("/home/bitcoin/.mynode/skip_fsck")

def has_sd_rw_error():
    return os.path.isfile("/tmp/sd_rw_error")


#==================================
# Dmesg Device Error Functions
#==================================
def has_oom_error():
    return os.path.isfile("/tmp/oom_error")
def clear_oom_error():
    delete_file("/tmp/oom_error")
    delete_file("/tmp/oom_info")
def set_oom_error(oom_error):
    touch("/tmp/oom_error")
    set_file_contents("/tmp/oom_info", oom_error)
def get_oom_error_info():
    try:
        with open("/tmp/oom_info", "r") as f:
            return f.read()
    except:
        return "ERROR"
    return "ERROR"

def has_usb_error():
    return os.path.isfile("/tmp/usb_error")
def set_usb_error():
    touch("/tmp/usb_error")
def clear_usb_error():
    clear_cached_data("dmesg_reset_usb_count")
    clear_cached_data("dmesg_io_error_count")
    delete_file("/tmp/usb_error")

#==================================
# Docker Functions
#==================================
def is_installing_docker_images():
    return os.path.isfile("/tmp/installing_docker_images")

def get_docker_image_build_status():
    status_code = get_service_status_code("docker_images")

    if status_code != 0:
        return "Failed... Retrying Later"

    if is_installing_docker_images():
        return "Installing..."
    else:
        return "Installation Complete"

    return "Unknown"

def get_docker_image_build_status_color():
    status_code = get_service_status_code("docker_images")
    if status_code != 0:
        return "red"
    return "green"

def reset_docker():
    # Delete docker data
    touch("/home/bitcoin/reset_docker")

    # Reset marker files
    os.system("rm -f /mnt/hdd/mynode/settings/webssh2_version")
    os.system("rm -f /mnt/hdd/mynode/settings/mempool_version")
    os.system("rm -f /mnt/hdd/mynode/settings/dojo_version")

    # Delete Dojo files
    os.system("rm -rf /opt/download/dojo")
    os.system("rm -rf /mnt/hdd/mynode/dojo")

    os.system("sync")
    reboot_device()

def get_docker_running_containers():
    containers = []

    # If docker not running, return empty
    if get_service_status_code("docker") != 0:
        return containers

    try:
        text = subprocess.check_output("docker ps --format '{{.Names}}'", shell=True, timeout=3).decode("utf8")
        containers = text.splitlines()
    except Exception as e:
        containers = [str(e)]
    return containers


#==================================
# USB Extras Functions
#==================================
def get_usb_extras():
    devices = []
    json_path = "/tmp/usb_extras.json"
    if os.path.isfile(json_path):
        try:
            with open(json_path) as f:
                devices = json.load(f)
        except Exception as e:
            log_message("EXCEPTION in get_usb_extras: " + str(e))
            devices = []
    log_message("get_usb_extras: {}".format(len(devices)))
    return devices
    

#==================================
# Bitcoin Functions
#==================================
def get_bitcoin_rpc_password():
    try:
        with open("/mnt/hdd/mynode/settings/.btcrpcpw", "r") as f:
            return f.read()
    except:
        return "ERROR"
    return "ERROR"

def stop_bitcoin():
    os.system("systemctl stop bitcoin")

def get_bitcoin_log_file():
    if is_testnet_enabled():
        return "/mnt/hdd/mynode/bitcoin/testnet3/debug.log"
    return "/mnt/hdd/mynode/bitcoin/debug.log"

def reset_bitcoin_env_file():
    os.system("echo 'BTCARGS=' > "+BITCOIN_ENV_FILE)

def delete_bitcoin_peer_database():
    os.system("rm -rf /mnt/hdd/mynode/bitcoin/peers.dat")
    os.system("rm -rf /mnt/hdd/mynode/bitcoin/testnet3/peers.dat")

def delete_bitcoin_data():
    os.system("rm -rf /mnt/hdd/mynode/bitcoin")
    os.system("rm -rf /mnt/hdd/mynode/quicksync/.quicksync_complete")
    #os.system("rm -rf /mnt/hdd/mynode/settings/.btcrpc_environment")
    #os.system("rm -rf /mnt/hdd/mynode/settings/.btcrpcpw")

def reset_bitcoin_peers():
    stop_bitcoin()
    delete_bitcoin_peer_database()
    reboot_device()

def reset_blockchain():
    stop_bitcoin()
    delete_bitcoin_data()
    reboot_device()


#==================================
# LND Functions
#==================================
def delete_lnd_data():
    os.system("rm -rf "+LND_DATA_FOLDER)
    os.system("rm -rf /tmp/lnd_deposit_address")
    os.system("rm -rf /home/bitcoin/.lnd-admin/credentials.json")
    os.system("rm -rf /mnt/hdd/mynode/settings/.lndpw")
    os.system("rm -rf /home/admin/.lnd/")
    return True

def delete_lnd_watchtower_client_data():
    os.system("rm -rf /mnt/hdd/mynode/lnd/data/graph/mainnet/wtclient.db")
    os.system("rm -rf /mnt/hdd/mynode/lnd/data/graph/mainnet/wtclient.db.last-compacted")
    return True

def delete_lnd_watchtower_server_data():
    os.system("rm -rf /mnt/hdd/mynode/lnd/data/watchtower")
    return True


#==================================
# Mainnet / Testnet Functions
#==================================
def is_testnet_enabled():
    return os.path.isfile("/mnt/hdd/mynode/settings/.testnet_enabled")
def enable_testnet():
    touch("/mnt/hdd/mynode/settings/.testnet_enabled")
def disable_testnet():
    delete_file("/mnt/hdd/mynode/settings/.testnet_enabled")
def toggle_testnet(): 
    if is_testnet_enabled():
        disable_testnet()
    else:
        enable_testnet()

#==================================
# Electrum Server Functions
#==================================
def stop_electrs():
    os.system("systemctl stop electrs")

def restart_electrs_actual():
    os.system("systemctl restart electrs")

def restart_electrs():
    t = Timer(0.1, restart_electrs_actual)
    t.start()

def delete_electrs_data():
    os.system("rm -rf /mnt/hdd/mynode/electrs/bitcoin")
    os.system("rm -rf /mnt/hdd/mynode/electrs/testnet")

def reset_electrs():
    stop_electrs()
    delete_electrs_data()
    restart_electrs()

#==================================
# RTL Functions
#==================================
def reset_rtl_config():
    os.system("rm -rf /mnt/hdd/mynode/rtl/RTL-Config.json")
    os.system("systemctl restart rtl")

#==================================
# Sphinx Relay Server Functions
#==================================
def stop_sphinxrelay():
    os.system("systemctl stop sphinxrelay")

def restart_sphinxrelay_actual():
    os.system("systemctl restart sphinxrelay")

def restart_sphinxrelay():
    t = Timer(0.1, restart_sphinxrelay_actual)
    t.start()

def delete_sphinxrelay_data():
    os.system("rm -rf /mnt/hdd/mynode/sphinxrelay/sphinx.db")
    os.system("rm -rf /opt/mynode/sphinxrelay/connection_string.txt")

def reset_sphinxrelay():
    stop_sphinxrelay()
    delete_sphinxrelay_data()
    restart_sphinxrelay()

#==================================
# Mempool Functions
#==================================
def clear_mempool_cache():
    os.system("rm -rf /mnt/hdd/mynode/mempool/data/*")
    os.system("rm -rf /mnt/hdd/mynode/mempool/mysql/data/*")
    os.system("sync")
    os.system("systemctl restart mempool")

#==================================
# Specter Functions
#==================================
def reset_specter_config():
    os.system("rm -rf /mnt/hdd/mynode/specter/config.json")
    os.system("systemctl restart specter")

#==================================
# BTC RPC Explorer Functions
#==================================
def is_btcrpcexplorer_token_enabled():
    if os.path.isfile("/mnt/hdd/mynode/settings/.btcrpcexplorer_disable_token"):
        return False
    return True

def enable_btcrpcexplorer_token():
    delete_file("/mnt/hdd/mynode/settings/.btcrpcexplorer_disable_token")
    if is_service_enabled("btcrpcexplorer"):
        restart_service("btcrpcexplorer")


def disable_btcrpcexplorer_token():
    touch("/mnt/hdd/mynode/settings/.btcrpcexplorer_disable_token")
    if is_service_enabled("btcrpcexplorer"):
        restart_service("btcrpcexplorer")

#==================================
# Tor Functions
#==================================
def reset_tor():
    os.system("rm -rf /var/lib/tor/*")
    os.system("rm -rf /mnt/hdd/mynode/tor_backup/*")
    os.system("rm -rf /mnt/hdd/mynode/bitcoin/onion_private_key")
    os.system("rm -rf /mnt/hdd/mynode/lnd/v2_onion_private_key")
    os.system("rm -rf /mnt/hdd/mynode/lnd/v3_onion_private_key")

def reset_tor_connections():
    stop_service("tor@default")
    os.system("rm -rf /var/lib/tor/*")
    start_service("tor@default")

def get_onion_url_ssh():
    if is_community_edition(): return "not_available"
    try:
        if os.path.isfile("/var/lib/tor/mynode_ssh/hostname"):
            with open("/var/lib/tor/mynode_ssh/hostname") as f:
                return f.read()
    except:
        pass
    return "error"

def get_onion_url_general():
    if is_community_edition(): return "not_available"
    try:
        if os.path.isfile("/var/lib/tor/mynode/hostname"):
            with open("/var/lib/tor/mynode/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_btc():
    if is_community_edition(): return "not_available"
    try:
        if os.path.isfile("/var/lib/tor/mynode_btc/hostname"):
            with open("/var/lib/tor/mynode_btc/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_lnd():
    if is_community_edition(): return "not_available"
    try:
        if os.path.isfile("/var/lib/tor/mynode_lnd/hostname"):
            with open("/var/lib/tor/mynode_lnd/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_electrs():
    if is_community_edition(): return "not_available"
    try:
        if os.path.isfile("/var/lib/tor/mynode_electrs/hostname"):
            with open("/var/lib/tor/mynode_electrs/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_lndhub():
    if is_community_edition(): return "not_available"
    try:
        if os.path.isfile("/var/lib/tor/mynode_lndhub/hostname"):
            with open("/var/lib/tor/mynode_lndhub/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_lnbits():
    if is_community_edition(): return "not_available"
    try:
        if os.path.isfile("/var/lib/tor/mynode_lnbits/hostname"):
            with open("/var/lib/tor/mynode_lnbits/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_btcpay():
    if is_community_edition(): return "not_available"
    try:
        if os.path.isfile("/var/lib/tor/mynode_btcpay/hostname"):
            with open("/var/lib/tor/mynode_btcpay/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_sphinxrelay():
    if is_community_edition(): return "not_available"
    try:
        if os.path.isfile("/var/lib/tor/mynode_sphinx/hostname"):
            with open("/var/lib/tor/mynode_sphinx/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_for_service(short_name):
    if is_community_edition(): return "not_available"
    try:
        if os.path.isfile("/var/lib/tor/mynode_{}/hostname".format(short_name)):
            with open("/var/lib/tor/mynode_{}/hostname".format(short_name)) as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_info_btc_v2():
    info = {}
    info["url"] = "unknown"
    info["pass"] = "unknown"
    try:
        if os.path.isfile("/var/lib/tor/mynode_btc_v2/hostname"):
            with open("/var/lib/tor/mynode_btc_v2/hostname") as f:
                content = f.read().strip()
                parts = content.split(" ")
                info["url"] = parts[0]
                info["pass"] = parts[1]
                return info
    except:
        pass
    return info

def get_tor_version():
    global cached_data
    if "tor_version" in cached_data:
        return cached_data["tor_version"]

    v = to_string( subprocess.check_output("tor --version | head -n 1 | egrep -o '[0-9\\.]+[0-9]'", shell=True) )
    v = v.strip()
    cached_data["tor_version"] = v
    return cached_data["tor_version"]


#==================================
# Firewall Functions
#==================================
def reload_firewall():
    os.system("ufw reload")

def get_firewall_rules():
    try:
        rules = to_string(subprocess.check_output("ufw status", shell=True).decode("utf8"))
    except:
        rules = "ERROR"
    return rules


#==================================
# SSO Functions
#==================================
def get_sso_token(short_name):
    if short_name == "btcrpcexplorer":
        token = get_file_contents("/opt/mynode/btc-rpc-explorer/token")
    elif short_name == "thunerhub":
        token = get_file_contents("/opt/mynode/thunderhub/.cookie")
    else:
        token = "UNKNOWN_APP"
    return to_string(token)

def get_sso_token_enabled(short_name):
    enabled = False
    if short_name == "btcrpcexplorer":
        enabled = is_btcrpcexplorer_token_enabled()
    return enabled


#==================================
# QR Code Functions
#==================================
def generate_qr_code(url):
    try:
        qr = qrcode.QRCode(version=1,
                        error_correction=qrcode.constants.ERROR_CORRECT_H,
                        box_size=5,
                        border=1)

        qr.add_data(url)
        qr.make(fit=True)
        img = qr.make_image()
        return img
    except Exception as e:
        log_message("generate_qr_code exception: {}".format(str(e)))
        return None