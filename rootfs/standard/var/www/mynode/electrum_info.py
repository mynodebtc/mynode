from bitcoin_info import get_bitcoin_block_height
from prometheus_client.parser import text_string_to_metric_families
from systemctl_info import *
import subprocess
import requests
import socket
import json
import os


electrum_server_current_block = None
electrs_active = False

def get_electrum_server_current_block():
    global electrum_server_current_block
    return electrum_server_current_block

def update_electrs_info():
    global electrum_server_current_block
    global electrs_active

    try:
        raw_data = requests.get("http://localhost:4224")
        prom_data = text_string_to_metric_families(raw_data.text)
        for family in prom_data:
            for sample in family.samples:
                if sample.name == "electrs_index_height":
                    electrum_server_current_block = int(sample.value)
                elif sample.name == "index_height":
                    electrum_server_current_block = int(sample.value)

        bitcoin_block_height = get_bitcoin_block_height()
        if electrum_server_current_block != None and bitcoin_block_height != None:
            if electrum_server_current_block > bitcoin_block_height - 2:
                os.system("touch /tmp/electrs_up_to_date")
                electrs_active = True
    except:
        pass

def is_electrs_active():
    global electrs_active
    if not is_service_enabled("electrs"):
        return False
    return electrs_active

def get_electrs_status():
    global electrum_server_current_block
    global electrs_active

    if not is_service_enabled("electrs"):
        return "Disabled"

    bitcoin_block_height = get_bitcoin_block_height()
    log = ""
    try:
        log += subprocess.check_output("journalctl --unit=electrs --no-pager | tail -n 100", shell=True)
    except:
        log += ""
    lines = log.splitlines()
    lines.reverse()
    for line in lines:
        # Electrs pre v9
        if "left to index)" in line:
            break
        elif "Checking if Bitcoin is synced..." in line or "NetworkInfo {" in line or "BlockchainInfo {" in line:
            return "Starting..."
        elif "opening DB at" in line or "enabling auto-compactions" in line:
            return "Starting..."
        elif "downloading 100000 block headers" in line or "downloading new block headers" in line:
            return "Getting headers..."
        elif "starting full compaction" in line:
            return "Compressing..."
        elif "enabling auto-compactions" in line:
            break
        elif "RPC server running on" in line:
            break
        # Electrs v9+
        elif "stopping Electrum RPC server" in line or "notified via SIG15" in line:
            return "Stopping..."
        elif "serving Electrum RPC on 0.0.0.0:50001" in line:
            break
        elif "indexing 2000 blocks" in line:
            break
        elif "indexing 1 blocks" in line:
            break
        elif "starting config compaction" in line or "starting headers compaction" in line or "starting txid compaction" in line:
            return "Compressing..."
        elif "starting funding compaction" in line or "starting spending compaction" in line:
            return "Compressing..."
        elif "loading 12 blocks" in line:
            break


    if electrum_server_current_block != None and bitcoin_block_height != None:
        if electrum_server_current_block < bitcoin_block_height - 10:
            percent = 100.0 * (float(electrum_server_current_block) / bitcoin_block_height)
            return "Syncing... {:.2f}%".format(abs(percent))
        else:
            electrs_active = True
            return "Running"
    return ""

def get_electrs_db_size(is_testnet=False):
    size = "Unknown"
    try:
        folder = "/mnt/hdd/mynode/electrs/bitcoin"
        if is_testnet:
            folder = "/mnt/hdd/mynode/electrs/testnet"
        size = subprocess.check_output("du -h "+folder+" | head -n1 | awk '{print $1;}'", shell=True)
    except Exception as e:
        size = "Error"
    return size

def get_from_electrum(method, params=[]):
    params = [params] if type(params) is not list else params
    s = socket.create_connection(('127.0.0.1', 50001))
    s.send(json.dumps({"id": 0, "method": method, "params": params}).encode() + b'\n')
    return json.loads(s.recv(99999)[:-1].decode())
