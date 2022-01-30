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
    latest = get_latest_price()
    if len(price_data) > 0:
        old = price_data[0]["price"]
        if latest != "N/A" and old != "N/A":
            return latest - old
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
            price_json_string = to_string(subprocess.check_output("torify curl https://api.coindesk.com/v1/bpi/currentprice.json", shell=True))
            data = json.loads(price_json_string)
            price = data["bpi"]["USD"]["rate_float"]

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
        log_message("UPDATE PRICE {}".format(price))

        # only keep 24 hours of updates
        while len(price_data) > 0:
            d = price_data[0]
            if d["time"] < now - 24*60*60:
                price_data.pop(0)
            else:
                break
