from config import *
from threading import Timer
import time
import os
import subprocess

# Globals
local_ip = "unknown"


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

def factory_reset():
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
    os.system("wget "+LATEST_VERSION_URL+" -O /usr/share/mynode/latest_version")
    os.system("wget "+LATEST_BETA_VERSION_URL+" -O /usr/share/mynode/latest_beta_version")
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

def reinstall_app(app):
    # Upgrade
    os.system("mkdir -p /home/admin/reinstall_logs")
    cmd = "/usr/bin/mynode_reinstall_app.sh {} > /home/admin/reinstall_logs/reinstall_{}.txt 2>&1".format(app,app)
    subprocess.call(cmd, shell=True)
    
    # Sync
    os.system("sync")
    time.sleep(1)

    # Reboot
    reboot_device()

def upgrade_device():
    # Upgrade
    os.system("mkdir -p /home/admin/upgrade_logs")
    cmd = "/usr/bin/mynode_upgrade.sh > /home/admin/upgrade_logs/upgrade_log_from_{}_upgrade.txt 2>&1".format(get_current_version())
    subprocess.call(cmd, shell=True)
    
    # Sync
    os.system("sync")
    time.sleep(1)

    # Reboot
    reboot_device()

def upgrade_device_beta():
    # Upgrade
    os.system("mkdir -p /home/admin/upgrade_logs")
    cmd = "/usr/bin/mynode_upgrade.sh beta > /home/admin/upgrade_logs/upgrade_log_from_{}_upgrade.txt 2>&1".format(get_current_version())
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

def get_system_date():
    date = subprocess.check_output('date', shell=True)
    date = date.strip()
    return date

def get_device_serial():
    serial = subprocess.check_output("cat /proc/cpuinfo | grep Serial | cut -d ' ' -f 2", shell=True)
    serial = serial.strip()
    if serial == "":
        # For VMs, use the UUID
        serial = subprocess.check_output("sudo dmidecode | grep UUID | cut -d ' ' -f 2", shell=True)
        serial = serial.strip()
    return serial

def get_device_type():
    device = subprocess.check_output("mynode-get-device-type", shell=True)
    return device

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


#==================================
# Service Status, Enabled, Logs, etc...
#==================================
def is_service_enabled(service_name):
    cmd = "systemctl is-enabled {}".format(service_name)
    try:
        subprocess.check_call(cmd, shell=True)
        return True
    except:
        return False
    return False

def get_service_status_code(service_name):
    code = os.system("systemctl status {} --no-pager".format(service_name))
    return code

def get_service_status_basic_text(service_name):
    if not is_service_enabled(service_name):
        return "Disabled"

    code = os.system("systemctl status {} --no-pager".format(service_name))
    if code == 0:
        return "Running"
    return "Error"

def get_service_status_color(service_name):
    if not is_service_enabled(service_name):
        return "gray"

    code = os.system("systemctl status {} --no-pager".format(service_name))
    if code == 0:
        return "green"
    return "red"

def get_journalctl_log(service_name):
    try:
        log = subprocess.check_output("journalctl -r --unit={} --no-pager | head -n 200".format(service_name), shell=True).decode("utf8")
    except:
        log = "ERROR"
    return log


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
def enable_quicksync():
    os.system("rm -rf /mnt/hdd/mynode/settings/quicksync_disabled")

def settings_disable_quicksync():
    stop_bitcoind()
    stop_quicksync()
    disable_quicksync()
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
    os.system('echo "quicksync_reset" > /mnt/hdd/mynode/.mynode_status')
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
    os.system("rm -rf /opt/mynode/.dojo")
    os.system("rm -rf /opt/mynode/dojo")

    os.system("sync")
    reboot_device()

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
    os.system("touch mnt/hdd/mynode/settings/.btc_lnd_tor_enabled")
    os.system("sync")

def disable_btc_lnd_tor():
    os.system("rm -f mnt/hdd/mynode/settings/.btc_lnd_tor_enabled")
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
