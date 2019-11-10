from bitcoin_info import get_bitcoin_block_height
from prometheus_client.parser import text_string_to_metric_families
import subprocess
import requests
import socket
import json


electrum_server_current_block = None
electrs_active = False

def get_electrum_server_current_block():
    global electrum_server_current_block
    return electrum_server_current_block

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
    global electrs_active
    return electrs_active

def get_electrs_status():
    global electrum_server_current_block
    global electrs_active
    bitcoin_block_height = get_bitcoin_block_height()
    log = ""
    try:
        log += subprocess.check_output("journalctl --unit=electrs --no-pager | tail -n 100", shell=True)
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
            electrs_active = True
            return "Running"
    return ""


def get_from_electrum(method, params=[]):
    params = [params] if type(params) is not list else params
    s = socket.create_connection(('127.0.0.1', 50001))
    s.send(json.dumps({"id": 0, "method": method, "params": params}).encode() + b'\n')
    return json.loads(s.recv(99999)[:-1].decode())
