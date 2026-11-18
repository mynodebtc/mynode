from bitcoin_info import get_bitcoin_block_height, get_bitcoin_version
from prometheus_client.parser import text_string_to_metric_families
from systemctl_info import *
from utilities import *
import subprocess
import requests
import socket
import json
import re
import os


electrum_server_current_block = None
electrs_active = False
electrs_version = None

def get_electrum_server_current_block():
    global electrum_server_current_block
    return electrum_server_current_block

def get_electrs_index_height():
    # electrs v0.9 - v0.11 publish the indexed height as a Prometheus metric
    try:
        raw_data = requests.get("http://localhost:4224", timeout=15)
        prom_data = text_string_to_metric_families(raw_data.text)
        for family in prom_data:
            for sample in family.samples:
                if sample.name == "electrs_index_height" or sample.name == "index_height":
                    return int(sample.value)
    except:
        pass

    # electrs v0.12+ has no index metrics, so ask the Electrum RPC for the tip it serves
    try:
        # A short timeout: a synced electrs answers in milliseconds, and while it indexes it
        # only answers between batches, where the journal below is the cheaper source
        response = get_from_electrum("blockchain.headers.subscribe", timeout=2)
        return int(response["result"]["height"])
    except:
        pass

    # While v0.12+ builds the index it only answers between batches, and a batch of large
    # blocks takes longer than the socket timeout above, so use the height it last logged.
    # Only lines from the running electrs count - after a reset the journal still holds the old
    # index's height, and the unit keeps its last InvocationID while stopped.
    try:
        if not is_service_active("electrs"):
            return None
        invocation_id = to_string(subprocess.check_output(
            ["systemctl", "show", "--property=InvocationID", "--value", "electrs"])).strip()
        if not re.match(r"^[0-9a-f]{32}$", invocation_id):
            return None
        log = to_string(subprocess.check_output(
            ["journalctl", "_SYSTEMD_INVOCATION_ID=" + invocation_id, "--no-pager", "--lines=200"]))
        heights = re.findall(r"height=([0-9]+): indexed", log)
        if len(heights) > 0:
            return int(heights[-1])
    except:
        pass

    return None

def update_electrs_info():
    global electrum_server_current_block
    global electrs_active

    try:
        height = get_electrs_index_height()
        if height != None:
            electrum_server_current_block = height

        bitcoin_block_height = get_bitcoin_block_height()
        if electrum_server_current_block != None and bitcoin_block_height != None:
            if electrum_server_current_block > bitcoin_block_height - 2:
                touch("/tmp/electrs_up_to_date")
                electrs_active = True
    except:
        pass

def clear_electrs_info():
    # The index was deleted, so forget the height it had reached. Apps that need electrs then
    # show "Waiting on Electrum", and wait_on_electrs.sh holds back their start, until the new
    # index catches up.
    global electrum_server_current_block
    global electrs_active
    electrum_server_current_block = None
    electrs_active = False
    delete_file("/tmp/electrs_up_to_date")

def get_electrs_version():
    global electrs_version
    if electrs_version == None:
        # The binary is installed by pre_electrs.sh, so it is missing until electrs is enabled
        try:
            electrs_version = to_string(subprocess.check_output("electrs --version", shell=True))
        except:
            return "Unknown"
    return "{}".format(electrs_version)

def is_electrs_v12_or_newer():
    electrs_match = re.search(r"([0-9]+)\.([0-9]+)\.", get_electrs_version())
    return electrs_match != None and (int(electrs_match.group(1)), int(electrs_match.group(2))) >= (0, 12)

def get_bitcoin_version_too_old_for_electrs():
    # electrs v0.12+ reads blocks through REST endpoints that arrived in Bitcoin Core 31, so it
    # cannot index on an older Bitcoin (such as the custom 29.x and Knots builds). Returns that
    # Bitcoin version so the page can explain the problem, or None when there is none.
    if not is_electrs_v12_or_newer():
        return None
    bitcoin_version = get_bitcoin_version().strip()
    bitcoin_match = re.match(r"v?([0-9]+)\.", bitcoin_version)
    if not bitcoin_match or int(bitcoin_match.group(1)) >= 31:
        return None
    return bitcoin_version

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
    compacting = False
    log = ""
    try:
        log += to_string(subprocess.check_output("journalctl --unit=electrs --no-pager | tail -n 100", shell=True))
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
        # Electrs v12+
        elif "indexed" in line and "blocks," in line:
            break
        elif "headers loaded" in line:
            break
        elif "started auto compactions" in line:
            # electrs v0.12+ builds the index with compaction off and turns it on at the tip.
            # Compacting that backlog can take a couple of hours, and no new blocks are indexed
            # (or logged) until it is done
            compacting = True
            break
        elif " CF " in line:
            return "Starting..."


    if electrum_server_current_block != None and bitcoin_block_height != None:
        if compacting and electrum_server_current_block < bitcoin_block_height:
            return "Compressing..."
        if electrum_server_current_block < bitcoin_block_height - 5:
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
        size = to_string(subprocess.check_output("du -h "+folder+" | head -n1 | awk '{print $1;}'", shell=True))
    except Exception as e:
        size = "Error"
    return size

def get_from_electrum(method, params=[], timeout=15):
    params = [params] if type(params) is not list else params
    s = socket.create_connection(('127.0.0.1', 50001), timeout=timeout)
    try:
        s.send(json.dumps({"id": 0, "method": method, "params": params}).encode() + b'\n')
        return json.loads(s.recv(99999)[:-1].decode())
    finally:
        s.close()
