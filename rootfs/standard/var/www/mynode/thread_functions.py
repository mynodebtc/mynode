import subprocess
import psutil
import os
from config import *
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from bitcoin_info import *
from lightning_info import *
from device_info import *
from utilities import *
from enable_disable_functions import *
from systemctl_info import *
from electrum_info import update_electrs_info
from price_info import update_price_info
from requests import get
import random

# Info to get from the update threads
has_updated_btc_info = False
cpu_usage = "..."
ram_usage = "..."
swap_usage = "..."
os_drive_usage_details = "..."
data_drive_usage_details = "..."
public_ip = "not_detected"

# Getters
def get_has_updated_btc_info():
    global has_updated_btc_info
    return has_updated_btc_info
def get_cpu_usage():
    global cpu_usage
    return cpu_usage
def get_os_drive_usage_details():
    global os_drive_usage_details
    return os_drive_usage_details
def get_data_drive_usage_details():
    global data_drive_usage_details
    return data_drive_usage_details
def get_public_ip():
    global public_ip
    return public_ip

# Updates device info every 60 seconds
device_info_call_count = 0
def update_device_info():
    global cpu_usage
    global os_drive_usage_details
    global data_drive_usage_details
    global device_info_call_count

    # Get drive info
    try:
        # Get throttled info (raspi only)
        reload_throttled_data()

        # Get CPU usage
        cpu_info = psutil.cpu_times_percent(interval=10.0, percpu=False)
        cpu_usage = "{:.1f}%".format(100.0 - cpu_info.idle)

        # Update every 24 hrs
        if device_info_call_count % 60*24 == 0:
            os_drive_usage_details = ""
            os_drive_usage_details += "<small>"
            os_drive_usage_details += "<b>App Storage</b><br/>"
            os_drive_usage_details += "<pre>" + run_linux_cmd("du -h -d1 /opt/mynode/", ignore_failure=True) + "</pre><br/>"
            os_drive_usage_details += "<b>User Storage</b><br/>"
            os_drive_usage_details += "<pre>" + run_linux_cmd("du -h -d1 /home/", ignore_failure=True) + "</pre><br/>"
            os_drive_usage_details += "<b>Rust Toolchain Storage</b><br/>"
            if os.path.isdir("/root/.cargo/"):
                os_drive_usage_details += "<pre>" + run_linux_cmd("du -h -d1 /root/.cargo/", ignore_failure=True) + "</pre><br/>"
            if os.path.isdir("/home/admin/.cargo/"):
                os_drive_usage_details += "<pre>" + run_linux_cmd("du -h -d1 /home/admin/.cargo/", ignore_failure=True) + "</pre><br/>"
            os_drive_usage_details += "</small>"

            data_drive_usage_details = ""
            data_drive_usage_details += "<small>"
            data_drive_usage_details += "<b>Data Storage</b><br/>"
            data_drive_usage_details += "<pre>" + run_linux_cmd("du -h -d1 /mnt/hdd/mynode/", ignore_failure=True) + "</pre><br/>"
            data_drive_usage_details += "</small>"

    except Exception as e:
        log_message("CAUGHT update_device_info EXCEPTION: " + str(e))
        return

    device_info_call_count = device_info_call_count + 1

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
                if remaining == 0 and bitcoin_block_height > 710000:
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
        log_message("CAUGHT update_bitcoin_main_info_thread EXCEPTION: " + str(e))


# Updates other bitcoin info every 60 seconds
def update_bitcoin_other_info_thread():
    try:
        # Get bitcoin info
        update_bitcoin_other_info()
    except Exception as e:
        log_message("CAUGHT update_bitcoin_other_info_thread EXCEPTION: " + str(e))


# Updates electrs info every 60 seconds
def update_electrs_info_thread():
    try:
        if is_service_enabled("electrs"):
            update_electrs_info()
    except Exception as e:
        log_message("CAUGHT update_electrs_info_thread EXCEPTION: " + str(e))


# Updates LND info every 60 seconds
def update_lnd_info_thread():
    try:
        # Get LND info
        update_lightning_info()
    except Exception as e:
        log_message("CAUGHT update_lnd_info_thread EXCEPTION: " + str(e))


# Updates price info every 5 minutes
def update_price_info_thread():
    try:
        # Get Price Info
        update_price_info()
    except Exception as e:
        log_message("CAUGHT update_price_info_thread EXCEPTION: " + str(e))


# Check every 3 hours
def find_public_ip():
    global public_ip

    #urls = ["https://mynodebtc.com/device_api/get_public_ip.php"]
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
            l = to_bytes(l).decode('utf-8')

            # Check for things like OOM, USB errors, etc...
            if "Out of memory" in l:
                set_oom_error(l)
                dmesg_log(l)
            elif "reset SuperSpeed Gen 1 USB device" in l:
                increment_cached_integer("dmesg_reset_usb_count")
                if get_cached_data("dmesg_reset_usb_count") >= 100:
                    set_usb_error()
                dmesg_log(l)
            elif "blk_update_request: I/O error, dev sd" in l:
                increment_cached_integer("dmesg_io_error_count")
                if get_cached_data("dmesg_io_error_count") >= 100:
                    set_usb_error()
                dmesg_log(l)
            else:
                #dmesg_log(l)
                pass
        except Exception as e:
            dmesg_log("dmesg exception: "+str(e))
    
