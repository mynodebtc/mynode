import subprocess
import psutil
import os
from config import *
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from bitcoin_info import *
from lightning_info import *
from device_info import *
from enable_disable_functions import *
from systemctl_info import *
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
        # Get throttled info (raspi only)
        reload_throttled_data()

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
        synced = False
        while True:
            # Get bitcoin info
            if update_bitcoin_main_info():
                # Mark on update complete
                has_updated_btc_info = True

                # Calculate sync status
                bitcoin_block_height = get_bitcoin_block_height()
                mynode_block_height = get_mynode_block_height()
                remaining = bitcoin_block_height - mynode_block_height
                if remaining == 0 and bitcoin_block_height > 680000:
                    synced = True
                    if not os.path.isfile(BITCOIN_SYNCED_FILE):
                        open(BITCOIN_SYNCED_FILE, 'a').close() # touch file
                elif remaining > 18:
                    synced = False
                    if os.path.isfile(BITCOIN_SYNCED_FILE):
                        os.remove(BITCOIN_SYNCED_FILE)

                # Poll slower if synced
                if synced:
                    time.sleep(15)
                else:
                    time.sleep(3)

            else:
                # Failed - try again in 10s
                time.sleep(10)

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
        if is_service_enabled("electrs"):
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


def dmesg_log_clear():
    f = open("/tmp/dmesg", "w")
    f.write("")
    f.close()
def dmesg_log(msg):
    print(msg)
    f = open("/tmp/dmesg", "a")
    f.write(msg)
    f.close()

# This will monitor dmesg for system errors or issues
def monitor_dmesg():
    dmesg_log_clear()
    dmesg_log("Starting dmesg log monitor")
    cmd = ["dmesg","--follow"]
    dmesg = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    while True:
        l = dmesg.stdout.readline()
        try:
            l = l.encode('utf-8', 'ignore').decode('utf-8')

            #TODO: Check for things like OOM, etc...
            if "Out of memory" in l:
                set_oom_error(l)
                dmesg_log(l)
            else:
                #dmesg_log(l)
                pass
        except Exception as e:
            dmesg_log("dmesg exception: "+str(e))
    
