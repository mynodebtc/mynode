from config import *
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
    except:
        latest_version = get_current_version()
    return latest_version


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
    return CONFIG["device_type"]


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
    return not os.path.isfile("/home/bitcoin/.mynode/quicksync_disabled") and \
           not os.path.isfile("/mnt/hdd/mynode/settings/quicksync_disabled")
def disable_quicksync():
    os.system("touch /home/bitcoin/.mynode/quicksync_disabled")
    os.system("touch /mnt/hdd/mynode/settings/quicksync_disabled")
def enable_quicksync():
    os.system("rm -rf /home/bitcoin/.mynode/quicksync_disabled")
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
    

def get_local_ip():
    global local_ip
    if local_ip == "unknown" or local_ip == "error":
        try:
            result = subprocess.check_output('hostname -I', shell=True)
            ips = result.split()
            local_ip = ips[0]
        except Exception as e:
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