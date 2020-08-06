import subprocess
import psutil
import os
from config import *
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from bitcoin_info import *
from lightning_info import *
from device_info import *
from enable_disable_functions import *
from electrum_info import update_electrs_info
from requests import get
import random

# Info to get from the update threads
has_updated_btc_info = False
drive_usage = "0%"
cpu_usage = "..."
ram_usage = "..."
swap_usage = "..."
device_temp = "..."
public_ip = "not_detected"


# Getters
def get_has_updated_btc_info():
    global has_updated_btc_info
    return has_updated_btc_info
def get_drive_usage():
    global drive_usage
    return drive_usage
def get_cpu_usage():
    global cpu_usage
    return cpu_usage
def get_ram_usage():
    global ram_usage
    return ram_usage
def get_swap_usage():
    global swap_usage
    return swap_usage
def get_device_temp():
    global device_temp
    return device_temp
def get_public_ip():
    global public_ip
    return public_ip

# Updates device info every 30 seconds
def update_device_info():
    global drive_usage
    global cpu_usage
    global ram_usage
    global swap_usage
    global device_temp

    # Get drive info
    try:
        # Get drive actual usage
        #results = subprocess.check_output(["du","-sh","/mnt/hdd/mynode/"])
        #drive_usage = results.split()[0]

        # Get drive percent usage
        results = subprocess.check_output("df -h /mnt/hdd | grep /dev | awk '{print $5}'", shell=True)
        drive_usage = results

        # Get RAM usage
        ram_info = psutil.virtual_memory()
        ram_usage = "{}%".format(ram_info.percent)

        # Get Swap Usage
        swap_info = psutil.swap_memory()
        swap_usage = "{}%".format(swap_info.percent)

        # Get CPU usage
        #cpu_usage = "{}%".format(psutil.cpu_percent(interval=30.0))
        cpu_info = psutil.cpu_times_percent(interval=30.0, percpu=False)
        cpu_usage = "{}%".format(100.0 - cpu_info.idle)

        # Get device temp
        results = subprocess.check_output("cat /sys/class/thermal/thermal_zone0/temp", shell=True)
        device_temp = int(results) / 1000

    except Exception as e:
        print("CAUGHT update_device_info EXCEPTION: " + str(e))
        return

# Updates main bitcoin info every 30 seconds
def update_bitcoin_main_info_thread():
    global has_updated_btc_info

    try:
        # Get bitcoin info
        if update_bitcoin_main_info():
            # Mark on update complete
            has_updated_btc_info = True

            # Calculate sync status
            bitcoin_block_height = get_bitcoin_block_height()
            mynode_block_height = get_mynode_block_height()
            remaining = bitcoin_block_height - mynode_block_height
            if remaining == 0 and bitcoin_block_height > 600000:
                if not os.path.isfile(BITCOIN_SYNCED_FILE):
                    open(BITCOIN_SYNCED_FILE, 'a').close() # touch file
            elif remaining > 18:
                if os.path.isfile(BITCOIN_SYNCED_FILE):
                    os.remove(BITCOIN_SYNCED_FILE)

    except Exception as e:
        print("CAUGHT update_bitcoin_main_info_thread EXCEPTION: " + str(e))


# Updates other bitcoin info every 60 seconds
def update_bitcoin_other_info_thread():
    try:
        # Get bitcoin info
        update_bitcoin_other_info()
    except Exception as e:
        print("CAUGHT update_bitcoin_other_info_thread EXCEPTION: " + str(e))


# Updates electrs info every 60 seconds
def update_electrs_info_thread():
    try:
        if is_electrs_enabled():
            update_electrs_info()
    except Exception as e:
        print("CAUGHT update_electrs_info_thread EXCEPTION: " + str(e))


# Updates LND info every 60 seconds
def update_lnd_info_thread():
    try:
        # Get LND info
        update_lightning_info()
    except Exception as e:
        print("CAUGHT update_lnd_info_thread EXCEPTION: " + str(e))


# Check every 3 hours
def find_public_ip():
    global public_ip

    #urls = ["http://mynodebtc.com/device_api/get_public_ip.php"]
    urls = ["https://api.ipify.org/","https://ip.seeip.org/","https://ip.seeip.org"]
    url = random.choice(urls)

    # Get public IP
    try:
        public_ip = get(url).text
    except Exception as e:
        public_ip = "Failed to find public IP. "


# Updated: Check ins now happen in different process. This will just restart the service to force a new check in.
def check_in():
    os.system("systemctl restart check_in")