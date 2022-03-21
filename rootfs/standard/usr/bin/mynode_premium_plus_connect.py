#!/usr/local/bin/python3
import os
import requests
import time
import subprocess
import json
import logging
from inotify_simple import INotify, flags
from systemd import journal
from utilities import *
from device_info import *
from drive_info import *
from application_info import *
from bitcoin_info import *
from lightning_info import *


PREMIUM_PLUS_CONNECT_URL = "https://www.mynodebtc.com/device_api/premium_plus_connect.php"

log = logging.getLogger('premium_plus_connect')
log.addHandler(journal.JournaldLogHandler())
log.setLevel(logging.INFO)
set_logger(log)

# Helper functions
def get_premium_plus_device_info():
    info = {}
    settings = get_premium_plus_settings()

    # Basic Info
    info["serial"] = get_device_serial()
    info["device_type"] = get_device_type()
    info["device_arch"] = get_device_arch()
    info["drive_size"] = get_mynode_drive_size()
    info["data_drive_usage"] = get_data_drive_usage()
    info["os_drive_usage"] = get_os_drive_usage()
    info["temperature"] = get_device_temp()
    info["total_ram"] = get_device_ram()
    info["ram_usage"] = get_ram_usage()
    info["swap_usage"] = get_swap_usage()
    info["uptime"] = get_system_uptime()

    # App status info
    if settings['sync_status']:
        info["app_info"] = get_all_applications_from_json_cache()

    return info

def get_premium_plus_bitcoin_info():
    info = {}
    settings = get_premium_plus_settings()

    if settings['sync_bitcoin_and_lightning']:
        #log_message("BITCOIN " + str(get_bitcoin_json_cache()))
        info = get_bitcoin_json_cache()
    return info

def get_premium_plus_lightning_info():
    info = {}
    settings = get_premium_plus_settings()

    if settings['sync_bitcoin_and_lightning']:
        #log_message("LIGHTNING " + str(get_lightning_json_cache()))
        info = get_lightning_json_cache()
    return info


def on_connect_success(connect_response_data):
    settings = get_premium_plus_settings()
    
    try:
        # Check for lnd watchtower, setup this device to use Premium+ Watchtower
        try:
            if "watchtower_uri" in connect_response_data:
                w = connect_response_data["watchtower_uri"]
                parts = w.split("@")
                pubkey = parts[0]
                output = run_lncli_command("lncli wtclient towers")
                info = json.loads(output)
                towers = info["towers"]
                
                found_watchtower = False
                for t in towers:
                    #log_message("EXISTING TOWER: {} active={}".format(t["pubkey"], t["active_session_candidate"]))
                    if t["pubkey"] == pubkey and t["active_session_candidate"] == True:
                        if settings["watchtower"]:
                            log_message("Found Premium+ Tower")
                        else:
                            log_message("Removing Premium+ Tower {}".format(pubkey))
                            run_lncli_command("lncli wtclient remove {}".format(pubkey))
                        found_watchtower = True
                if not found_watchtower:
                    log_message("Adding Premium+ Tower {}".format(w))
                    run_lncli_command("lncli wtclient add {}".format(w))

        except Exception as e:
            log_message("on_connect_success exception: {}".format(str(e)))
    except Exception as e:
        log_message("on_connect_success exception: {}".format(str(e)))
        return


# Update hourly
def premium_plus_connect():

    # Check in
    data = {
        "serial": get_device_serial(),
        "version": get_current_version(),
        "token": get_premium_plus_token(),
        "settings": json.dumps(get_premium_plus_settings()),
        "device_info": json.dumps(get_premium_plus_device_info()),
        "bitcoin_info": json.dumps(get_premium_plus_bitcoin_info()),
        "lightning_info": json.dumps(get_premium_plus_lightning_info()),
        "product_key": get_product_key(),
    }
    
    response = make_tor_request(PREMIUM_PLUS_CONNECT_URL, data)
    update_premium_plus_last_sync_time()
    if response == None:
        set_premium_plus_token_status("CONNECTION_ERROR")
        log_message("Premium+ Connect Error: Connection Failed")
        return False

    if response.status_code != 200:
        set_premium_plus_token_status("CONNECTION_ERROR")
        log_message("Premium+ Connect Error: Status Code {}".format(response.status_code))
        return False

    try:
        info = json.loads(response.text)
    except Exception as e:
        log_message("Premium+ Connect Error: Error Parsing JSON - {}".format(str(e)))
        return False

    if "error" in info:
        set_premium_plus_token_status(info["error"])
        return False
    elif "status" in info:
        set_premium_plus_token_status(info["status"])
        if info["status"] == "OK":
            log_message("Premium+ Connect Success!")
            log_message(response.text)
            on_connect_success(info)
        else:
            log_message("Premium+ Connect Error: Status ({})".format(info["status"]))
    else:
        log_message("Premium+ Connect Error: Missing Info {}".format(response.text))
        return False

    return True

# Run premium plus update consistently
if __name__ == "__main__":
    update_in_min = 15 # Update every 15 minutes
    update_ms = update_in_min * 60 * 1000 

    while True:
        try:
            # Wait for drive to be mounted
            while not is_mynode_drive_mounted():
                log_message("Checking if drive mounted...")
                time.sleep(10)
            log_message("Drive mounted!")

            # Wait on token
            log_message("Looking for Premium+ Token...")
            while not os.path.isfile("/home/bitcoin/.mynode/.premium_plus_token"):
                time.sleep(10)
            log_message("Token found!")
            premium_plus_connect()

            # Watch for updates
            log_message("")
            log_message("Watching for file changes or 1hr...")
            inotify = INotify()
            watch_flags = flags.CREATE | flags.DELETE | flags.MODIFY | flags.DELETE_SELF
            wd = inotify.add_watch('/home/bitcoin/.mynode/', watch_flags)
            for event in inotify.read(timeout=update_ms):
                log_message("File changed: " + str(event))
            log_message("Running connect again")
        except Exception as e:
            log_message("Error: {}".format(e))
            time.sleep(60)
