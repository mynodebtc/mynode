from flask import Blueprint, render_template, session, abort, Markup, request, redirect
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
from prometheus_client.parser import text_string_to_metric_families
from bitcoin_info import *
from device_info import get_local_ip, skipped_product_key
import requests
import json
import time
import subprocess

mynode_electrum_server = Blueprint('mynode_electrum_server',__name__)

electrum_server_current_block = None
eelctrs_active = False


def update_electrs_info():
    global electrum_server_current_block

    try:
        raw_data = requests.get("http://localhost:4224")
        prom_data = text_string_to_metric_families(raw_data.text)
        for family in prom_data:
            for sample in family.samples:
                if sample.name == "electrs_index_height":
                    electrum_server_current_block = int(sample.value)
    except:
        pass

def is_electrs_active():
    global eelctrs_active
    return eelctrs_active

def get_electrs_status():
    global electrum_server_current_block
    global eelctrs_active
    bitcoin_block_height = get_bitcoin_block_height()
    log = ""
    try:
        log += subprocess.check_output("tail -n 100 /var/log/electrs.log.1", shell=True)
    except:
        log += ""
    try:
        log += subprocess.check_output("tail -n 100 /var/log/electrs.log", shell=True)
    except:
        log += ""
    lines = log.splitlines()
    lines.reverse()
    for line in lines:
        if "left to index)" in line:
            break
        elif "Checking if Bitcoin is synced..." in line or "NetworkInfo {" in line or "BlockchainInfo {" in line:
            return "Starting..."
        elif "downloading 100000 block headers" in line:
            return "Downloading headers..."
        elif "starting full compaction" in line:
            return "Compressing data..."
        elif "enabling auto-compactions" in line:
            break
        elif "RPC server running on" in line:
            break

    if electrum_server_current_block != None and bitcoin_block_height != None:
        if electrum_server_current_block < bitcoin_block_height - 10:
            percent = 100.0 * (float(electrum_server_current_block) / bitcoin_block_height)
            return "Syncing... {:.2f}%".format(abs(percent))
        else:
            eelctrs_active = True
            return "Running"
    return ""


def get_electrum_server_current_block():
    global electrum_server_current_block
    return electrum_server_current_block

### Page functions
@mynode_electrum_server.route("/electrum-server")
def electrum_server_page():
    # Make sure data is up to date
    update_electrs_info()

    # Get latest info
    current_block = get_electrum_server_current_block()
    if current_block == None:
        current_block = "Unknown"
    status = get_electrs_status()

    #server_url = get_local_ip() + ":50002:s"
    server_ip = get_local_ip()
    server_standard_port = "50001"
    server_secure_port = "50002"

    # Get Onion URLs
    electrs_onion_hostname = "..."
    electrs_onion_command = "..."
    if os.path.isfile("/var/lib/tor/mynode/hostname"):
        with open("/var/lib/tor/mynode/hostname") as f:
            electrs_onion_hostname = f.read().strip()
            electrs_onion_command = "./electrum -1 -s {}:50002:s -p socks5:localhost:9050".format(electrs_onion_hostname)
    else:
        electrs_onion_hostname = "disabled"
        electrs_onion_command = "disabled"

    # Load page
    templateData = {
        "title": "myNode Electrum Server",
        "port": 50002,
        "status": status,
        "product_key_skipped": skipped_product_key(),
        "current_block": current_block,
        #"server_url": server_url,
        "server_ip": server_ip,
        "server_standard_port": server_standard_port,
        "server_secure_port": server_secure_port,
        "electrs_onion_hostname": electrs_onion_hostname,
        "electrs_onion_command": electrs_onion_command
    }
    return render_template('electrum_server.html', **templateData)
