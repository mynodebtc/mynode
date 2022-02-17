#!/usr/local/bin/python3
import os
import requests
import time
import subprocess
import logging
from inotify_simple import INotify, flags
from systemd import journal
import random

PREMIUM_PLUS_CONNECT_URL = "https://www.mynodebtc.com/device_api/premium_plus_connect.php"

log = logging.getLogger('premium_plus_connect')
log.addHandler(journal.JournaldLogHandler())
log.setLevel(logging.INFO)

# Helper functions
def log_message(msg):
    global log
    print(msg)
    log.info(msg)

def set_premium_plus_token_error(msg):
    os.system("echo '{}' > /home/bitcoin/.mynode/.premium_plus_token_error".format(msg))
def delete_premium_plus_token_error():
    os.system("rm -rf /home/bitcoin/.mynode/.premium_plus_token_error")
    os.system("rm -rf /mnt/hdd/mynode/settings/.premium_plus_token_error")
def has_premium_plus_token_error():
    if os.path.isfile("/home/bitcoin/.mynode/.premium_plus_token_error") or \
       os.path.isfile("/mnt/hdd/mynode/settings/.premium_plus_token_error"):
        return True
    return False

def get_current_version():
    current_version = "0.0"
    try:
        with open("/usr/share/mynode/version", "r") as f:
            current_version = f.read().strip()
    except:
        current_version = "error"
    return current_version
def get_device_type():
    device = subprocess.check_output("mynode-get-device-type", shell=True).decode("utf-8").strip()
    return device
def get_device_arch():
    arch = subprocess.check_output("uname -m", shell=True).decode("utf-8").strip()
    return arch
def get_device_serial():
    serial = subprocess.check_output("mynode-get-device-serial", shell=True).decode("utf-8").strip()
    return serial
def has_premium_plus_token():
    return os.path.isfile("/home/bitcoin/.mynode/.premium_plus_token") or \
           os.path.isfile("/mnt/hdd/mynode/settings/.premium_plus_token")
def get_premium_plus_token():
    token = "no_token"
    if not has_premium_plus_token():
        return "no_token"

    try:
        if os.path.isfile("/home/bitcoin/.mynode/.premium_plus_token"):
            with open("/home/bitcoin/.mynode/.premium_plus_token", "r") as f:
                token = f.read().strip()
        elif os.path.isfile("/mnt/hdd/mynode/settings/.premium_plus_token"):
            with open("/mnt/hdd/mynode/settings/.premium_plus_token", "r") as f:
                token = f.read().strip()
    except:
        token = "token_error"
    return token
def get_product_key():
    try:
        with open("/home/bitcoin/.mynode/.product_key", "r") as f:
            product_key = f.read().strip()
    except:
        product_key = "product_key_error"
    return product_key
def is_drive_mounted():
    mounted = True
    try:
        # Command fails and throws exception if not mounted
        output = subprocess.check_output(f"grep -qs '/mnt/hdd ext4' /proc/mounts", shell=True).decode("utf-8") 
    except:
        mounted = False
    return mounted
def get_drive_size():
    size = -1
    if not is_drive_mounted():
        return -3
    try:
        size = subprocess.check_output("df /mnt/hdd | grep /dev | awk '{print $2}'", shell=True).strip()
        size = int(size) / 1000 / 1000
    except Exception as e:
        size = -2
    return size
def get_drive_usage():
    return "TODO"

# Update hourly
def premium_plus_connect():

    # Check in
    token = get_premium_plus_token()
    data = {
        "serial": get_device_serial(),
        "device_type": get_device_type(),
        "device_arch": get_device_arch(),
        "version": get_current_version(),
        "token": get_premium_plus_token(),
        "product_key": get_product_key(),
        "drive_size": get_drive_size(),
        "drive_usage": get_drive_usage(),
    }

    # Setup tor proxy
    session = requests.session()
    session.proxies = {}
    session.proxies['http'] = 'socks5h://localhost:9050'
    session.proxies['https'] = 'socks5h://localhost:9050'

    # Check In
    fail_count = 0
    premium_plus_connect_success = False
    while not premium_plus_connect_success:
        try:
            # Use tor for check in unless there have been tor 5 failures in a row
            r = None
            if (fail_count+1) % 5 == 0:
                r = requests.post(PREMIUM_PLUS_CONNECT_URL, data=data, timeout=20)
            else:
                r = session.post(PREMIUM_PLUS_CONNECT_URL, data=data, timeout=20)
            
            if r.status_code == 200:
                if r.text == "OK":
                    log_message("Premium+ Connect Success: {}".format(r.text))
                else:
                    set_premium_plus_token_error(r.text)
                    log_message("Check In Returned Error: {}".format(r.text))

                os.system("rm -f /tmp/premium_plus_connect_error")
                premium_plus_connect_success = True
            else:
                log_message("Premium+ Connect Failed. Retrying... Code {}".format(r.status_code))
        except Exception as e:
            log_message("Premium+ Connect Failed. Retrying... Exception {}".format(e))

        if not premium_plus_connect_success:
            # Check in failed, try again in 1 minute
            os.system("touch /tmp/premium_plus_connect_error")
            time.sleep(60)
            fail_count = fail_count + 1

    return True

# Run premium plus update every hour
if __name__ == "__main__":
    one_hour_in_ms = 60 * 60 * 1000

    while True:
        try:
            # Wait for drive to be mounted
            while not is_drive_mounted():
                log_message("Checking if drive mounted...")
                time.sleep(10)
            log_message("Drive mounted!")

            # Wait on token
            log_message("Waiting on Premium+ Token")
            while not os.path.isfile("/home/bitcoin/.mynode/.premium_plus_token"):
                time.sleep(10)
            log_message("Token found!")
            premium_plus_connect()

            # Watch for updates
            inotify = INotify()
            watch_flags = flags.CREATE | flags.DELETE | flags.MODIFY | flags.DELETE_SELF
            wd = inotify.add_watch('/home/bitcoin/.mynode/', watch_flags)
            for event in inotify.read(timeout=one_hour_in_ms):
                log_message("File changed: " + str(event))
            log_message("Running connect again: " + str(event))
            premium_plus_connect()
        except Exception as e:
            log_message("Error: {}".format(e))
            time.sleep(60)
