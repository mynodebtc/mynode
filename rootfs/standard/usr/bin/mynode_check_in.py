#!/usr/local/bin/python3
import os
import requests
import time
import subprocess
import random
import logging
from systemd import journal
from utilities import *
from drive_info import *
from device_info import *

CHECKIN_URL = "https://www.mynodebtc.com/device_api/check_in.php"

log = logging.getLogger('check_in')
log.addHandler(journal.JournaldLogHandler())
log.setLevel(logging.INFO)
set_logger(log)

latest_version_check_count = 0

# Helper functions
def get_quicksync_enabled():
    enabled = 1
    if not is_mynode_drive_mounted():
        return -3
    if os.path.isfile("/mnt/hdd/mynode/settings/quicksync_disabled"):
        enabled = 0
    return enabled

def check_for_new_mynode_version():
    global latest_version_check_count
    # Chances of refreshing version
    #   Note: Hard limit forces day 5 to 100%
    # 
    # A 30% chance per day is:  A 35% chance per day is:  A 40% chance per day is:  A 45% chance per day is:
    #  1 day(s): 30%             1 day(s): 35%             1 day(s): 40%             1 day(s): 45%
    #  2 day(s): 51%             2 day(s): 57%             2 day(s): 64%             2 day(s): 69%
    #  3 day(s): 65%             3 day(s): 72%             3 day(s): 78%             3 day(s): 83%
    #  5 day(s): 83%             5 day(s): 88%             5 day(s): 92%             5 day(s): 94%
    #  7 day(s): 91%             7 day(s): 95%             7 day(s): 97%             7 day(s): 98%
    # A 50% chance per day is:  A 55% chance per day is:  A 60% chance per day is:  A 65% chance per day is:
    #  1 day(s): 50%             1 day(s): 55%             1 day(s): 60%             1 day(s): 65%
    #  2 day(s): 75%             2 day(s): 79%             2 day(s): 84%             2 day(s): 87%
    #  3 day(s): 87%             3 day(s): 90%             3 day(s): 93%             3 day(s): 95%
    #  5 day(s): 96%             5 day(s): 98%             5 day(s): 99%             5 day(s): 99%
    #  7 day(s): 99.2%           7 day(s): 99.6%           7 day(s): 99.8%           7 day(s): 99.9%
    if latest_version_check_count % 5 == 0 or random.randint(1, 100) <= 40:
        log_message("Version Check Count ({}) - Checking for new version!".format(latest_version_check_count))
        os.system("/usr/bin/mynode_get_latest_version.sh")
    else:
        log_message("Version Check Count ({}) - Skipping version check".format(latest_version_check_count))
    latest_version_check_count = latest_version_check_count + 1

# Checkin every 24 hours
def check_in():

    # Check in
    product_key = get_product_key()
    data = {
        "serial": get_device_serial(),
        "device_type": get_device_type(),
        "device_arch": get_device_arch(),
        "version": get_current_version(),
        "product_key": product_key,
        "drive_size": get_mynode_drive_size(),
        "quicksync_enabled": get_quicksync_enabled(),
    }

    # Check for new version (not every time to spread out upgrades)
    check_for_new_mynode_version()

    # Setup tor proxy
    session = requests.session()
    session.proxies = {}
    session.proxies['http'] = 'socks5h://localhost:9050'
    session.proxies['https'] = 'socks5h://localhost:9050'

    # Check In
    fail_count = 0
    check_in_success = False
    while not check_in_success:
        try:
            # Use tor for check in unless there have been tor 5 failures in a row
            r = None
            if (fail_count+1) % 5 == 0:
                r = requests.post(CHECKIN_URL, data=data, timeout=20)
            else:
                r = session.post(CHECKIN_URL, data=data, timeout=20)
            
            if r.status_code == 200:
                if r.text == "OK":
                    log_message("Check In Success: {}".format(r.text))

                    if product_key != "community_edition":
                        unset_skipped_product_key()
                    delete_product_key_error()
                else:
                    os.system("echo '{}' > /home/bitcoin/.mynode/.product_key_error".format(r.text))
                    log_message("Check In Returned Error: {}".format(r.text))

                os.system("rm -f /tmp/check_in_error")
                check_in_success = True
            else:
                log_message("Check In Failed. Retrying... Code {}".format(r.status_code))
        except Exception as e:
            log_message("Check In Failed. Retrying... Exception {}".format(e))

        if not check_in_success:
            # Check in failed, try again in 3 minutes
            os.system("touch /tmp/check_in_error")
            time.sleep(120)
            fail_count = fail_count + 1

    return True

# Run check in every 24 hours
if __name__ == "__main__":
    delay = 180
    while True:
        time.sleep(delay)   # Delay before first checkin so drive is likely mounted
        check_in()
        time.sleep(60*60*24 - delay)
