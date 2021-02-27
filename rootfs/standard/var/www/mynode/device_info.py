from config import *
from threading import Timer
from werkzeug.routing import RequestRedirect
from flask import flash
from enable_disable_functions import *
from lightning_info import is_lnd_ready, get_lnd_status, get_lnd_status_color
from systemctl_info import *
from electrum_info import get_electrs_status, is_electrs_active
from bitcoin_info import get_bitcoin_status, is_bitcoind_synced
import time
import json
import os
import subprocess
import random
import string
import redis

# Globals
local_ip = "unknown"
cached_data = {}
warning_data = {}

#==================================
# Utilities
#==================================
def get_file_contents(filename):
    contents = "UNKNOWN"
    try:
        with open(filename, "r") as f:
            contents = f.read().strip()
    except:
        contents = "ERROR"
    return contents

def set_file_contents(filename, data):
    try:
        with open(filename, "w") as f:
            f.write(data)
        os.system("sync")
        return True
    except:
        return False
    return False

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
    os.system("systemctl disable btc_rpc_explorer --no-pager")
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
        file1 = "/home/admin/upgrade_logs/upgrade_log_from_{}_upgrade.txt".format(get_current_version())
        file2 = "/home/admin/upgrade_logs/upgrade_log_latest.txt"
        cmd = "/usr/bin/mynode_upgrade.sh 2>&1 | tee {} {}".format(file1, file2)
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
        file1 = "/home/admin/upgrade_logs/upgrade_log_from_{}_upgrade.txt".format(get_current_version())
        file2 = "/home/admin/upgrade_logs/upgrade_log_latest.txt"
        cmd = "/usr/bin/mynode_upgrade.sh beta 2>&1 | tee {} {}".format(file1, file2)
        subprocess.call(cmd, shell=True)
        
        # Sync
        os.system("sync")
        time.sleep(1)

        # Reboot
        reboot_device()

def did_upgrade_fail():
    return os.path.isfile("/mnt/hdd/mynode/settings/upgrade_error")

def get_recent_upgrade_logs():
    logs=""
    current_version = get_current_version()
    for i in range(1,6):
        filename = "/home/admin/upgrade_logs/upgrade_log_{}_post_{}.txt".format(current_version, i)
        try:
            with open(filename, "r") as f:
                logs = logs + "===========================================================\n"
                logs = logs + "=== Upgrade Attempt #{}\n".format(i)
                logs = logs + "===========================================================\n\n\n"
                logs = logs + f.read().decode("utf8")
        except:
            pass
    return logs

def has_checkin_error():
    return os.path.isfile("/tmp/check_in_error")


#==================================
# Manage Apps
#==================================
def get_app_current_version(app):
    version = "unknown"
    filename1 = "/home/bitcoin/.mynode/"+app+"_version"
    filename2 = "/mnt/hdd/mynode/settings/"+app+"_version"
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


# This is going to be the "old" way to install apps
def reinstall_app(app):
    if not is_upgrade_running():
        mark_upgrade_started()

        # Upgrade
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
    uptime = uptime.strip()
    return uptime

def get_system_uptime_in_seconds():
    uptime = subprocess.check_output('awk \'{print $1}\' /proc/uptime', shell=True)
    uptime = int(float(uptime.strip()))
    return uptime

def get_system_time_in_ms():
    return int(round(time.time() * 1000))

def get_system_date():
    date = subprocess.check_output('date', shell=True)
    date = date.strip()
    return date

def get_device_serial():
    global cached_data
    if "serial" in cached_data:
        return cached_data["serial"]

    serial = subprocess.check_output("mynode-get-device-serial", shell=True)
    serial = serial.strip()

    cached_data["serial"] = serial
    return serial

def get_device_type():
    global cached_data
    if "device_type" in cached_data:
        return cached_data["device_type"]
    
    device = subprocess.check_output("mynode-get-device-type", shell=True).strip()
    cached_data["device_type"] = device
    return device

def get_device_ram():
    global cached_data
    if "ram" in cached_data:
        return cached_data["ram"]

    ram = subprocess.check_output("free --giga | grep Mem | awk '{print $2}'", shell=True).strip()
    cached_data["ram"] = ram
    return ram

def get_local_ip():
    local_ip = "unknown"
    try:
        local_ip = subprocess.check_output('/usr/bin/get_local_ip.py', shell=True).strip()
    except:
        local_ip = "error"

    return local_ip

def get_device_changelog():
    changelog = ""
    try:
        changelog = subprocess.check_output(["cat", "/usr/share/mynode/changelog"])
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
# Log functions (non-systemd based)
#==================================
def get_file_log(file_path):
    status_log = ""

    if not os.path.isfile(file_path):
        return "MISSING FILE"

    try:
        status_log = subprocess.check_output(["tail","-n","200",file_path]).decode("utf8")
        lines = status_log.split('\n')
        lines.reverse()
        status_log = '\n'.join(lines)
    except:
        status_log = "ERROR"
    return status_log

#==================================
# Specific Service Status / Colors
#==================================
def get_bitcoin_status_and_color():
    status = ""
    color = "gray"
    if get_service_status_code("bitcoind") == 0:
        status = get_bitcoin_status()
        color = "green"
    else:
        status = "Error"
        color = "red"
    return status,color

def get_lnd_status_and_color():
    status = get_lnd_status()
    color = get_lnd_status_color()
    return status,color

def get_vpn_status_and_color():
    status = ""
    color = "gray"
    if is_vpn_enabled():
        color = get_service_status_color("vpn")
        status_code = get_service_status_code("vpn")
        if status_code != 0:
            status = "Unknown"
        else:
            if os.path.isfile("/home/pivpn/ovpns/mynode_vpn.ovpn"):
                status = "Running"
            else:
                status = "Setting up..."
    return status,color

def get_rtl_status_and_color():
    status = "Lightning Wallet"
    color = "gray"
    if is_lnd_ready():
        if is_rtl_enabled():
            status_code = get_service_status_code("rtl")
            if status_code != 0:
                color = "red"
            else:
                color = "green"
    else:
        status = "Waiting on LND..."
    return status,color

def get_lnbits_status_and_color():
    color = "gray"
    status = "Lightning Wallet"
    if is_lnd_ready():
        if is_lnbits_enabled():
            status_code = get_service_status_code("lnbits")
            if status_code != 0:
                lnbits_status_color = "red"
            else:
                lnbits_status_color = "green"
    else:
        status = "Waiting on LND..."
    return status,color

def get_thunderhub_status_and_color():
    color = "gray"
    status = "Lightning Wallet"
    if is_lnd_ready():
        if is_thunderhub_enabled():
            status_code = get_service_status_code("thunderhub")
            if status_code != 0:
                color = "red"
            else:
                color = "green"
    else:
        status = "Waiting on LND..."
    return status,color

def get_ckbunker_status_and_color():
    status = "Coldcard Signing Tool"
    color = "gray"
    if is_bitcoind_synced():
        if is_ckbunker_enabled():
            color = get_service_status_color("lndhub")
    else:
        status = "Waiting on Bitcoin..."
    return status,color

def get_sphinxrelay_status_and_color():
    color = "gray"
    status = "Chat"
    if is_lnd_ready():
        if is_sphinxrelay_enabled():
            status_code = get_service_status_code("sphinxrelay")
            if status_code != 0:
                color = "red"
            else:
                color = "green"
    else:
        status = "Waiting on LND..."
    return status,color

def get_lndhub_status_and_color():
    status = "BlueWallet Backend"
    color = "gray"
    if is_lnd_ready():
        if is_lndhub_enabled():
            color = get_service_status_color("lndhub")
    else:
        status = "Waiting on LND..."
    return status,color

def get_btcpayserver_status_and_color():
    status = "Merchant Tool"
    color = "gray"
    if is_lnd_ready():
        color = get_service_status_color("btcpayserver")
    else:
        status = "Waiting on LND..."
    return status,color

def get_electrs_status_and_color():
    status = ""
    color = "gray"
    if is_electrs_enabled():
        status_code = get_service_status_code("electrs")
        color = get_service_status_color("electrs")
        if status_code == 0:
            status = get_electrs_status()
    return status,color

def get_btcrpcexplorer_status_and_color_and_ready():
    status = "BTC RPC Explorer"
    color = "gray"
    ready = False
    if is_btcrpcexplorer_enabled():
        if is_bitcoind_synced():
            if is_electrs_active():
                color = get_service_status_color("btc_rpc_explorer")
                status_code = get_service_status_code("btc_rpc_explorer")
                if status_code == 0:
                    ready = True
            else:
                color = "yellow"
                status = "Waiting on Electrum..."
        else:
            color = "yellow"
            status = "Waiting on bitcoin..."
    return status,color,ready

def get_caravan_status_and_color():
    status = ""
    color = "gray"
    if is_caravan_enabled():
        color = get_service_status_color("caravan")
        status = "Running"
    return status,color

def get_specter_status_and_color():
    status = ""
    color = "gray"
    if is_specter_enabled():
        color = get_service_status_color("specter")
        status = "Running"
    return status,color

def get_mempool_status_and_color():
    status = "Mempool Viewer"
    color = "gray"
    if is_mempoolspace_enabled():
        if is_installing_docker_images():
            color = "yellow"
            status = "Installing..."
        else:
            color = get_service_status_color("mempoolspace")
    return status,color

#==================================
# Data Storage Functions
#==================================
def set_data(key, value):
    r = redis.Redis(host='localhost', port=6379, db=0)
    mynode_key = "mynode_" + key
    return r.set(mynode_key, value)

def get_data(key):
    r = redis.Redis(host='localhost', port=6379, db=0)
    mynode_key = "mynode_" + key
    return r.get(mynode_key)

#==================================
# UI Functions
#==================================
def read_ui_settings():
    ui_hdd_file = '/mnt/hdd/mynode/settings/ui.json'
    ui_mynode_file = '/home/bitcoin/.mynode/ui.json'

    # read ui.json from HDD
    if os.path.isfile(ui_hdd_file):
        with open(ui_hdd_file, 'r') as fp:
            ui_settings = json.load(fp)
    # read ui.json from mynode
    elif os.path.isfile(ui_mynode_file):
        with open(ui_mynode_file, 'r') as fp:
            ui_settings = json.load(fp)
    # if ui.json is not found anywhere, use default settings
    else:
        ui_settings = {'darkmode': False}

    # Set reseller
    ui_settings["reseller"] = is_device_from_reseller()

    return ui_settings

def write_ui_settings(ui_settings):
    ui_hdd_file = '/mnt/hdd/mynode/settings/ui.json'
    ui_mynode_file = '/home/bitcoin/.mynode/ui.json'

    try:
        with open(ui_hdd_file, 'w') as fp:
            json.dump(ui_settings, fp)
    except:
        pass

    with open(ui_mynode_file, 'w') as fp:
        json.dump(ui_settings, fp)

def is_darkmode_enabled():
    ui_settings = read_ui_settings()
    return ui_settings['darkmode']

def disable_darkmode():
    ui_settings = read_ui_settings()
    ui_settings['darkmode'] = False
    write_ui_settings(ui_settings)

def enable_darkmode():
    ui_settings = read_ui_settings()
    ui_settings['darkmode'] = True
    write_ui_settings(ui_settings)

def toggle_darkmode():
    if is_darkmode_enabled():
        disable_darkmode()
    else:
        enable_darkmode()

def is_https_forced():
    return os.path.isfile('/home/bitcoin/.mynode/https_forced')

def force_https(force):
    if force:
        os.system("touch /home/bitcoin/.mynode/https_forced")
    else:
        os.system("rm -f /home/bitcoin/.mynode/https_forced")

def get_flask_secret_key():
    if os.path.isfile("/home/bitcoin/.mynode/flask_secret_key"):
        key = get_file_contents("/home/bitcoin/.mynode/flask_secret_key")
    else:
        letters = string.ascii_letters
        key = ''.join(random.choice(letters) for i in range(32))
        set_file_contents("/home/bitcoin/.mynode/flask_secret_key", key)
    return key


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
    stop_bitcoind()
    stop_quicksync()
    disable_quicksync() # Try disable again (some users had disable fail)
    delete_quicksync_data()
    reboot_device()

def settings_enable_quicksync():
    stop_bitcoind()
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
    stop_bitcoind()
    stop_quicksync()
    delete_bitcoin_data()
    delete_quicksync_data()
    enable_quicksync()
    reboot_device()


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

def has_sd_rw_error():
    return os.path.isfile("/tmp/sd_rw_error")


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
    os.system("rm -f /mnt/hdd/mynode/settings/webssh2_url")
    os.system("rm -f /mnt/hdd/mynode/settings/mempoolspace_url")
    os.system("rm -f /mnt/hdd/mynode/settings/dojo_url")

    # Delete Dojo files
    os.system("rm -rf /opt/download/dojo")
    os.system("rm -rf /mnt/hdd/mynode/dojo")

    os.system("sync")
    reboot_device()

def get_docker_running_containers():
    containers = []
    try:
        text = subprocess.check_output("docker ps --format '{{.Names}}'", shell=True, timeout=3).decode("utf8")
        containers = text.splitlines()
    except:
        containers = ["ERROR"]
    return containers

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

def stop_bitcoind():
    os.system("systemctl stop bitcoind")

def reset_bitcoin_env_file():
    os.system("echo 'BTCARGS=' > "+BITCOIN_ENV_FILE)

def delete_bitcoin_data():
    os.system("rm -rf /mnt/hdd/mynode/bitcoin")
    os.system("rm -rf /mnt/hdd/mynode/quicksync/.quicksync_complete")
    os.system("rm -rf /mnt/hdd/mynode/settings/.btcrpc_environment")
    os.system("rm -rf /mnt/hdd/mynode/settings/.btcrpcpw")

def reset_blockchain():
    stop_bitcoind()
    delete_bitcoin_data()
    reboot_device()


#==================================
# LND Functions
#==================================
def stop_lnd():
    os.system("systemctl stop lnd")

def restart_lnd():
    os.system("systemctl restart lnd")

def delete_lnd_data():
    #os.system("rm -f "+LND_WALLET_FILE)
    os.system("rm -rf "+LND_DATA_FOLDER)
    os.system("rm -rf /home/bitcoin/.lnd-admin/credentials.json")
    os.system("rm -rf /mnt/hdd/mynode/settings/.lndpw")
    os.system("rm -rf /home/admin/.lnd/")
    return True


#==================================
# Electrum Server Functions
#==================================
def stop_electrs():
    os.system("systemctl stop electrs")

def delete_electrs_data():
    os.system("rm -rf /mnt/hdd/mynode/electrs")

def reset_electrs():
    stop_electrs()
    delete_electrs_data()
    reboot_device()



#==================================
# Tor Functions
#==================================
def reset_tor():
    os.system("rm -rf /var/lib/tor/*")
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
    try:
        if os.path.isfile("/var/lib/tor/mynode_ssh/hostname"):
            with open("/var/lib/tor/mynode_ssh/hostname") as f:
                return f.read()
    except:
        pass
    return "error"

def get_onion_url_general():
    try:
        if os.path.isfile("/var/lib/tor/mynode/hostname"):
            with open("/var/lib/tor/mynode/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_btc():
    try:
        if os.path.isfile("/var/lib/tor/mynode_btc/hostname"):
            with open("/var/lib/tor/mynode_btc/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_lnd():
    try:
        if os.path.isfile("/var/lib/tor/mynode_lnd/hostname"):
            with open("/var/lib/tor/mynode_lnd/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_electrs():
    try:
        if os.path.isfile("/var/lib/tor/mynode_electrs/hostname"):
            with open("/var/lib/tor/mynode_electrs/hostname") as f:
                return f.read().strip()
    except:
        pass
    return "error"

def get_onion_url_btcpay():
    try:
        if os.path.isfile("/var/lib/tor/mynode_btcpay/hostname"):
            with open("/var/lib/tor/mynode_btcpay/hostname") as f:
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

    cached_data["tor_version"] = subprocess.check_output("tor --version | egrep -o '[0-9\\.]+'", shell=True).strip().strip(".")
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
# BTC RPC Explorer Functions
#==================================
def get_btcrpcexplorer_sso_token():
    return get_file_contents("/opt/mynode/btc-rpc-explorer/token")
