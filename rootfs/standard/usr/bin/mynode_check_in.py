#!/usr/local/bin/python3
import os
import requests
import time
import subprocess

CHECKIN_URL = "https://www.mynodebtc.com/device_api/check_in.php"

# Helper functions
def unset_skipped_product_key():
    os.system("rm -rf /home/bitcoin/.mynode/.product_key_skipped")
    os.system("rm -rf /mnt/hdd/mynode/settings/.product_key_skipped")
def delete_product_key_error():
    os.system("rm -rf /home/bitcoin/.mynode/.product_key_error")
    os.system("rm -rf /mnt/hdd/mynode/settings/.product_key_error")
def get_current_version():
    current_version = "0.0"
    try:
        with open("/usr/share/mynode/version", "r") as f:
            current_version = f.read().strip()
    except:
        current_version = "error"
    return current_version
def get_device_type():
    device = subprocess.check_output("mynode-get-device-type", shell=True).strip()
    return device
def get_device_serial():
    serial = subprocess.check_output("mynode-get-device-serial", shell=True).strip()
    return serial
def skipped_product_key():
    return os.path.isfile("/home/bitcoin/.mynode/.product_key_skipped") or \
           os.path.isfile("/mnt/hdd/mynode/settings/.product_key_skipped")
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

# Checkin every 24 hours
def check_in():

    # Check in
    product_key = get_product_key()
    data = {
        "serial": get_device_serial(),
        "device_type": get_device_type(),
        "version": get_current_version(),
        "product_key": product_key
    }

    # Check for new version
    os.system("/usr/bin/mynode_get_latest_version.sh")

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
                r = requests.post(CHECKIN_URL, data=data, timeout=15)
            else:
                r = session.post(CHECKIN_URL, data=data, timeout=15)
            
            if r.status_code == 200:
                if r.text == "OK":
                    os.system("printf \"%s | Check In Success: {} \\n\" \"$(date)\" >> /tmp/check_in_status".format(r.text))

                    if product_key != "community_edition":
                        unset_skipped_product_key()
                    delete_product_key_error()
                else:
                    os.system("echo '{}' > /home/bitcoin/.mynode/.product_key_error".format(r.text))
                    os.system("printf \"%s | Check In Returned Error: {} \\n\" \"$(date)\" >> /tmp/check_in_status".format(r.text))

                os.system("rm -f /tmp/check_in_error")
                check_in_success = True
            else:
                os.system("printf \"%s | Check In Failed. Retrying... Code {} \\n\" \"$(date)\" >> /tmp/check_in_status".format(r.status_code))
        except Exception as e:
            os.system("printf \"%s | Check In Failed. Retrying... Exception {} \\n\" \"$(date)\" >> /tmp/check_in_status".format(e))

        if not check_in_success:
            # Check in failed, try again in 3 minutes
            os.system("touch /tmp/check_in_error")
            time.sleep(120)
            fail_count = fail_count + 1

    return True

# Run check in every 24 hours
if __name__ == "__main__":
    while True:
        check_in()
        time.sleep(60*60*24)
