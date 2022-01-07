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

    # Reset password
    os.system("/usr/bin/mynode_chpasswd.sh bolt")

    # Reboot
    reboot_device()

def check_and_mark_reboot_action(tmp_marker):
    if os.path.isfile("/tmp/{}".format(tmp_marker)):
        flash(u'Refresh prevented - action already triggered', category="error")
        raise RequestRedirect("/")
    os.system("touch /tmp/{}".format(tmp_marker))

def reload_throttled_data():
    global cached_data
    if os.path.isfile("/tmp/get_throttled_data"):
        cached_data["get_throttled_data"] = get_file_contents("/tmp/get_throttled_data")

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
    os.system("touch /tmp/upgrade_started")
    os.system("sync")

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
    log = get_file_contents("/home/admin/upgrade_logs/upgrade_log_latest.txt").decode("utf8")
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
                    log["log"] = cleanup_log( get_file_contents(fullpath).decode("utf8") )
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
    uptime = subprocess.check_output('awk \'{print int($1/86400)" days "int($1%86400/3600)" hour(s) "int(($1%3600)/60)" minute(s) "int($1%60)" seconds(s)"}\' /proc/uptime', shell=True)
    uptime = to_string(uptime.strip())
    return uptime

def get_system_uptime_in_seconds():
    uptime = subprocess.check_output('awk \'{print $1}\' /proc/uptime', shell=True)
    uptime = int(float(uptime.strip()))
    return uptime

def get_system_time_in_ms():
    return int(round(time.time() * 1000))

def get_system_date():
    date = subprocess.check_output('date', shell=True)
    date = to_string(date.strip())
    return date

def get_device_serial():
    global cached_data
    if "serial" in cached_data:
        return cached_data["serial"]

    serial = subprocess.check_output("mynode-get-device-serial", shell=True)
    serial = to_string(serial.strip())

    cached_data["serial"] = serial
    return serial

def get_device_type():
    global cached_data
    if "device_type" in cached_data:
        return cached_data["device_type"]
    
    device = subprocess.check_output("mynode-get-device-type", shell=True).strip()
    cached_data["device_type"] = to_string(device)
    return device

def get_device_arch():
    global cached_data
    if "device_arch" in cached_data:
        return cached_data["device_arch"]

    arch = subprocess.check_output("uname -m", shell=True).decode("utf-8").strip()
    cached_data["device_arch"] = to_string(arch)
    return arch

def get_device_ram():
    global cached_data
    if "ram" in cached_data:
        return cached_data["ram"]

    ram = subprocess.check_output("free --giga | grep Mem | awk '{print $2}'", shell=True).strip()
    cached_data["ram"] = to_string(ram)
    return ram

def get_local_ip():
    local_ip = "unknown"
    try:
        local_ip = subprocess.check_output('/usr/bin/get_local_ip.py', shell=True).strip()
    except:
        local_ip = "error"

    return to_string(local_ip)

def get_device_changelog():
    changelog = ""
    try:
        changelog = subprocess.check_output(["cat", "/usr/share/mynode/changelog"])
    except:
        changelog = "ERROR"
    return to_string(changelog)

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
    return get_file_contents("/mnt/hdd/mynode/settings/swap_size")

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
    return get_file_contents("/tmp/.clone_state")

def get_clone_error():
    return get_file_contents("/tmp/.clone_error")

def get_clone_progress():
    return get_file_contents("/tmp/.clone_progress")

def get_clone_source_drive():
    return get_file_contents("/tmp/.clone_source")

def get_clone_target_drive():
    return get_file_contents("/tmp/.clone_target")

def get_clone_target_drive_has_mynode():
    return os.path.isfile("/tmp/.clone_target_drive_has_mynode")

def get_drive_info(drive):
    data = {}
    data["name"] = "NOT_FOUND"
    try:
        lsblk_output = subprocess.check_output("lsblk -io KNAME,TYPE,SIZE,MODEL,VENDOR /dev/{} | grep disk".format(drive), shell=True).decode("utf-8") 
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
    return os.path.isfile('/home/bitcoin/.mynode/https_forced')

def force_https(force):
    if force:
        os.system("touch /home/bitcoin/.mynode/https_forced")
    else:
        os.system("rm -f /home/bitcoin/.mynode/https_forced")

# Regen cert
def regen_https_cert():
    os.system("rm -rf /home/bitcoin/.mynode/https")
    os.system("rm -rf /mnt/hdd/mynode/settings/https")
    os.system("/usr/bin/mynode_gen_cert.sh https 825")
    os.system("sync")
    os.system("systemctl restart nginx")

def get_flask_secret_key():
    if os.path.isfile("/home/bitcoin/.mynode/flask_secret_key"):
        key = get_file_contents("/home/bitcoin/.mynode/flask_secret_key")
    else:
        letters = string.ascii_letters
        key = ''.join(random.choice(letters) for i in range(32))
        set_file_contents("/home/bitcoin/.mynode/flask_secret_key", key)
    return key

def get_flask_session_timeout():
    try:
        if os.path.isfile("/home/bitcoin/.mynode/flask_session_timeout"):
            timeout = get_file_contents("/home/bitcoin/.mynode/flask_session_timeout")
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

def get_randomize_balances():
    return os.path.isfile('/home/bitcoin/.mynode/randomize_balances')

def set_randomize_balances(randomize):
    if randomize:
        os.system("touch /home/bitcoin/.mynode/randomize_balances")
    else:
        os.system("rm -f /home/bitcoin/.mynode/randomize_balances")

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
    os.system("touch /mnt/hdd/mynode/settings/uploader")
def unset_uploader():
    os.system("rm -rf /mnt/hdd/mynode/settings/uploader")


#==================================
# QuickSync Functions
#==================================
def is_quicksync_enabled():
    return not os.path.isfile("/mnt/hdd/mynode/settings/quicksync_disabled")
def disable_quicksync():
    os.system("touch /mnt/hdd/mynode/settings/quicksync_disabled")
    os.system("sync")
def enable_quicksync():
    os.system("rm -rf /mnt/hdd/mynode/settings/quicksync_disabled")

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
            log = subprocess.check_output(["mynode-get-quicksync-status"]).decode("utf8")
        except:
            log = "ERROR"
    else:
        log = "Disabled"
    return log


#==================================
# Product Key Functions
#==================================
def set_skipped_product_key():
    os.system("touch /home/bitcoin/.mynode/.product_key_skipped")
    os.system("touch /mnt/hdd/mynode/settings/.product_key_skipped")
def unset_skipped_product_key():
    os.system("rm -rf /home/bitcoin/.mynode/.product_key_skipped")
    os.system("rm -rf /mnt/hdd/mynode/settings/.product_key_skipped")
def skipped_product_key():
    return os.path.isfile("/home/bitcoin/.mynode/.product_key_skipped") or \
           os.path.isfile("/mnt/hdd/mynode/settings/.product_key_skipped")
def is_community_edition():
    return skipped_product_key()

def delete_product_key():
    os.system("rm -rf /home/bitcoin/.mynode/.product_key")
    os.system("rm -rf /mnt/hdd/mynode/settings/.product_key")
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
def delete_product_key_error():
    os.system("rm -rf /home/bitcoin/.mynode/.product_key_error")
    os.system("rm -rf /mnt/hdd/mynode/settings/.product_key_error")


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
        os.system("touch /home/bitcoin/.mynode/skip_fsck")
    else:
        os.system("rm -f /home/bitcoin/.mynode/skip_fsck")
    os.system("sync")
def skip_fsck():
    return os.path.isfile("/home/bitcoin/.mynode/skip_fsck")

def has_sd_rw_error():
    return os.path.isfile("/tmp/sd_rw_error")


#==================================
# Out of Memory Error Functions
#==================================
def has_oom_error():
    return os.path.isfile("/tmp/oom_error")
def clear_oom_error():
    os.system("rm -f /tmp/oom_error")
    os.system("rm -f /tmp/oom_info")
def set_oom_error(oom_error):
    os.system("touch /tmp/oom_error")
    set_file_contents("/tmp/oom_info", oom_error)
def get_oom_error_info():
    try:
        with open("/tmp/oom_info", "r") as f:
            return f.read()
    except:
        return "ERROR"
    return "ERROR"


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
    os.system("touch /home/bitcoin/reset_docker")

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

    # TODO: switch to subprocess after switch to python3 for web ui (timeout doesn't work w/ subprocess32, causes issues)
    try:
        text = subprocess32.check_output("docker ps --format '{{.Names}}'", shell=True, timeout=3).decode("utf8")
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

def delete_bitcoin_data():
    os.system("rm -rf /mnt/hdd/mynode/bitcoin")
    os.system("rm -rf /mnt/hdd/mynode/quicksync/.quicksync_complete")
    os.system("rm -rf /mnt/hdd/mynode/settings/.btcrpc_environment")
    os.system("rm -rf /mnt/hdd/mynode/settings/.btcrpcpw")

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


#==================================
# Mainnet / Testnet Functions
#==================================
def is_testnet_enabled():
    return os.path.isfile("/mnt/hdd/mynode/settings/.testnet_enabled")
def enable_testnet():
    os.system("touch /mnt/hdd/mynode/settings/.testnet_enabled")
    os.system("sync")
def disable_testnet():
    os.system("rm -f /mnt/hdd/mynode/settings/.testnet_enabled")
    os.system("sync")
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
    os.system("rm -rf /mnt/hdd/mynode/settings/.btcrpcexplorer_disable_token")
    os.system("sync")
    if is_service_enabled("btcrpcexplorer"):
        restart_service("btcrpcexplorer")


def disable_btcrpcexplorer_token():
    os.system("touch /mnt/hdd/mynode/settings/.btcrpcexplorer_disable_token")
    os.system("sync")
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

def is_btc_lnd_tor_enabled():
    return os.path.isfile("/mnt/hdd/mynode/settings/.btc_lnd_tor_enabled")

def enable_btc_lnd_tor():
    os.system("touch /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled")
    os.system("sync")

def disable_btc_lnd_tor():
    os.system("rm -f /mnt/hdd/mynode/settings/.btc_lnd_tor_enabled")
    os.system("sync")

def is_aptget_tor_enabled():
    return os.path.isfile("/mnt/hdd/mynode/settings/torify_apt_get")

def enable_aptget_tor():
    os.system("touch /mnt/hdd/mynode/settings/torify_apt_get")
    os.system("sync")

def disable_aptget_tor():
    os.system("rm -f /mnt/hdd/mynode/settings/torify_apt_get")
    os.system("sync")

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
        rules = subprocess.check_output("ufw status", shell=True).decode("utf8")
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
        token = "UNKOWN_APP"
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
        print("generate_qr_code exception: {}".format(str(e)))
        return None