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

def parse_mempool_price(data):
    return float(data["USD"])

def parse_kraken_price(data):
    # Last trade price of the only pair requested
    return float(next(iter(data["result"].values()))["c"][0])

# Tried in order. The onion needs no Tor exit, so exit-node blocking can't break it.
PRICE_SOURCES = [
    ("mempool.space onion", "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion/api/v1/prices", parse_mempool_price),
    ("Kraken", "https://api.kraken.com/0/public/Ticker?pair=XBTUSD", parse_kraken_price),
]

def fetch_price():
    errors = []
    for name, url, parse in PRICE_SOURCES:
        try:
            output = subprocess.check_output(["torify", "curl", "--max-time", "20", "--silent", "--fail", url], stderr=subprocess.DEVNULL, timeout=25)
            price = parse(json.loads(to_string(output)))
            if price > 0:
                return price
            errors.append("{}: bad price {}".format(name, price))
        except Exception as e:
            errors.append("{}: {}".format(name, str(e)))
    log_message("update_price_info failed: {}".format(" | ".join(errors)))
    return "ERR"

def update_price_info():
    global price_data

    if get_ui_setting("price_ticker"):
        price = fetch_price()

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
