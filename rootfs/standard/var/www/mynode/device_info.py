from config import *
from threading import Timer
import time
import os
import subprocess

# Globals
local_ip = "unknown"

# Functions
def get_current_version():
    current_version = "0.0"
    try:
        with open("/usr/share/mynode/version", "r") as f:
            current_version = f.read().strip()
    except:
        current_version = "error"
    return current_version


def update_latest_version():
    os.system("wget "+LATEST_VERSION_URL+" -O /usr/share/mynode/latest_version")
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


def did_upgrade_fail():
    return os.path.isfile("/mnt/hdd/mynode/settings/upgrade_error")


def get_system_uptime():
    uptime = subprocess.check_output('awk \'{print int($1/86400)" days "int($1%86400/3600)" hour(s) "int(($1%3600)/60)" minute(s) "int($1%60)" seconds(s)"}\' /proc/uptime', shell=True)
    uptime = uptime.strip()
    return uptime


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


def is_uploader():
    return os.path.isfile("/home/bitcoin/.mynode/uploader") or \
           os.path.isfile("/mnt/hdd/mynode/settings/uploader")
def set_uploader():
    os.system("touch /home/bitcoin/.mynode/uploader")
    os.system("touch /mnt/hdd/mynode/settings/uploader")
def unset_uploader():
    os.system("rm -rf /home/bitcoin/.mynode/uploader")
    os.system("rm -rf /mnt/hdd/mynode/settings/uploader")


def is_quicksync_enabled():
    return not os.path.isfile("/mnt/hdd/mynode/settings/quicksync_disabled")
def disable_quicksync():
    os.system("touch /mnt/hdd/mynode/settings/quicksync_disabled")
def enable_quicksync():
    os.system("rm -rf /mnt/hdd/mynode/settings/quicksync_disabled")


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
    
def has_fsck_error():
    return os.path.isfile("/tmp/fsck_error")
def get_fsck_results():
    try:
        with open("/tmp/fsck_results", "r") as f:
            return f.read()
    except:
        return "ERROR"
    return "ERROR"

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
    return os.path.isfile("/home/bitcoin/.mynode/.hashedpw")

def get_bitcoin_rpc_password():
    try:
        with open("/mnt/hdd/mynode/settings/.btcrpcpw", "r") as f:
            return f.read()
    except:
        return "ERROR"
    return "ERROR"

def stop_bitcoind():
    os.system("systemctl stop bitcoind")

def stop_lnd():
    os.system("systemctl stop lnd")

def restart_lnd():
    os.system("systemctl restart lnd")

def stop_quicksync():
    os.system("systemctl stop quicksync")


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


def reset_bitcoin_env_file():
    os.system("echo 'BTCARGS=' > "+BITCOIN_ENV_FILE)


def delete_bitcoin_data():
    os.system("rm -rf /mnt/hdd/mynode/bitcoin")
    os.system("rm -rf /mnt/hdd/mynode/quicksync/.quicksync_complete")
    os.system("rm -rf /mnt/hdd/mynode/settings/.btcrpc_environment")
    os.system("rm -rf /mnt/hdd/mynode/settings/.btcrpcpw")


def delete_quicksync_data():
    os.system("rm -rf /mnt/hdd/mynode/quicksync")
    os.system("rm -rf /home/bitcoin/.config/transmission") # Old dir
    os.system("rm -rf /mnt/hdd/mynode/.config/transmission")


def delete_lnd_data():
    #os.system("rm -f "+LND_WALLET_FILE)
    os.system("rm -rf "+LND_DATA_FOLDER)
    os.system("rm -rf /home/bitcoin/.lnd-admin/credentials.json")
    os.system("rm -rf /mnt/hdd/mynode/settings/.lndpw")
    os.system("rm -rf /home/admin/.lnd/")
    return True


def reboot_device():
    stop_bitcoind()
    stop_lnd()
    os.system("sync")
    os.system("reboot")


def shutdown_device():
    stop_bitcoind()
    stop_lnd()
    os.system("sync")
    os.system("shutdown -h now")


def reset_blockchain():
    stop_bitcoind()
    delete_bitcoin_data()
    reboot_device()


def restart_quicksync():
    os.system('echo "quicksync_reset" > /mnt/hdd/mynode/.mynode_status')
    stop_bitcoind()
    stop_quicksync()
    delete_bitcoin_data()
    delete_quicksync_data()
    enable_quicksync()
    reboot_device()


def reset_tor():
    os.system("rm -rf /var/lib/tor/*")
    os.system("rm -rf /mnt/hdd/mynode/bitcoin/onion_private_key")
    os.system("rm -rf /mnt/hdd/mynode/lnd/v2_onion_private_key")


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
