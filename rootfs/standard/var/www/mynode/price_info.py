from utilities import *
from device_info import *
import subprocess
import json
import time
import os


price_data = []

def get_latest_price():
    global price_data
    if len(price_data) > 0:
        return price_data[len(price_data) - 1]["price"]
    return "MISSING"

def get_price_diff_24hrs():
    global price_data
    try:
        msg_calc = "n/a"
        latest = get_latest_price()
        if len(price_data) > 0:
            old = price_data[0]["price"]
            if latest != "N/A" and latest != "ERR" and old != "N/A" and old != "ERR":
                msg_calc = f"({latest} - {old})"
                return latest - old
    except Exception as e:
        log_message("ERROR get_price_diff_24hrs: {} | {}".format(msg_calc, str(e)))
    return 0.0

def get_price_up_down_flat_24hrs():
    diff = get_price_diff_24hrs()
    if diff > 10:
        return "up"
    elif diff < -10:
        return "down"
    return "flat"

def update_price_info():
    global price_data

    if get_ui_setting("price_ticker"):
        price = "N/A"
        try:
            price_api_endpoint = "https://blockchain.info/ticker"
            price_json_string = to_string(subprocess.check_output(f"torify curl --max-time 15 --silent {price_api_endpoint}", shell=True))
            data = json.loads(price_json_string)
            price = data["USD"]["last"]

        except Exception as e:
            log_message("update_price_info EXCEPTION: {}".format(str(e)))
            price = "ERR"
            pass

        # Add latest price
        now = int(time.time())
        d = {}
        d["time"] = now
        d["price"] = price
        price_data.append(d)
        #log_message("UPDATE PRICE {}".format(price))

        # only keep 24 hours of updates
        while len(price_data) > 0:
            d = price_data[0]
            if d["time"] < now - 24*60*60:
                price_data.pop(0)
            else:
                break
