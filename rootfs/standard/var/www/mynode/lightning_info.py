import copy
import requests
import subprocess
import os
import time
import re
from threading import Timer
from bitcoin_info import *

# Variables
lightning_info = None
lnd_ready = False

LND_FOLDER = "/mnt/hdd/mynode/lnd/"
MACAROON_FILE = "/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon"
WALLET_FILE = "/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/wallet.db"
TLS_CERT_FILE = "/mnt/hdd/mynode/lnd/tls.cert"
CHANNEL_BACKUP_FILE = "/home/bitcoin/lnd_backup/channel.backup"
LND_REST_PORT = "10080"

# Functions
def update_lightning_info():
    global lightning_info
    global lnd_ready

    # Get latest LN info
    lightning_info = lnd_get("/getinfo")

    # Set is LND ready
    if lightning_info != None and "synced_to_chain" in lightning_info and lightning_info['synced_to_chain']:
        lnd_ready = True
    
    # Check for LND de-sync (this can happen unfortunately)
    #   See https://github.com/lightningnetwork/lnd/issues/1909
    #   See https://github.com/bitcoin/bitcoin/pull/14687
    # Hopefully patch comes soon to enable TCP keepalive to prevent this from happening
    if lnd_ready and lightning_info != None and "synced_to_chain" in lightning_info and not lightning_info['synced_to_chain']:
        os.system("echo 'LND De-sync!!!' >> /tmp/lnd_failures")
        os.system("uptime >> /tmp/lnd_failures")
        restart_lnd()

    return True


def get_lightning_info():
    global lightning_info
    return copy.deepcopy(lightning_info)

def is_lnd_ready():
    global lnd_ready
    return lnd_ready

def lnd_get(path):
    try:
        macaroon = get_macaroon()
        headers = {"Grpc-Metadata-macaroon":macaroon}
        r = requests.get("https://localhost:"+LND_REST_PORT+"/v1"+path, verify=TLS_CERT_FILE,headers=headers)
    except Exception as e:
        return str(e)
    return r.json()

def gen_new_wallet_seed():
    seed = subprocess.check_output("python3 /usr/bin/gen_seed.py", shell=True)
    return seed

def restart_lnd_actual():
    global lnd_ready
    lnd_ready = False
    os.system("systemctl restart lnd")
    os.system("systemctl restart lnd_unlock")

def restart_lnd():
    t = Timer(1.0, restart_lnd_actual)
    t.start()

def get_macaroon():
    m = subprocess.check_output("xxd -ps -u -c 1000 "+MACAROON_FILE, shell=True)
    return m.strip()

def lnd_wallet_exists():
    return os.path.isfile(WALLET_FILE)

def unlock_wallet():
    os.system("/usr/bin/expect /usr/bin/unlock_lnd.tcl")

def create_wallet(seed):
    try:
        subprocess.check_call("create_lnd_wallet.tcl \""+seed+"\"", shell=True)

        t = Timer(1.0, unlock_wallet)
        t.start()
        
        # Sync FS and sleep so the success redirect understands the wallet was created
        os.system("sync")
        time.sleep(2)

        return True
    except:
        return False

def is_lnd_logged_in():
    try:
        macaroon = get_macaroon()
        headers = {"Grpc-Metadata-macaroon":macaroon}
        r = requests.get("https://localhost:"+LND_REST_PORT+"/v1/getinfo", verify=TLS_CERT_FILE,headers=headers)
        if r.status_code == 200 and r.json():
            return True
        return False
    except:
        return False

def lnd_channel_backup_exists():
    return os.path.isfile(CHANNEL_BACKUP_FILE)

def get_lnd_status():
    if not lnd_wallet_exists():
        return "Please create wallet..."

    if not is_lnd_logged_in():
        return "Logging in..."

    if is_lnd_ready():
        return "Running"

    log = subprocess.check_output("tail -n 100 /var/log/lnd.log", shell=True)
    lines = log.splitlines()
    lines.reverse()
    for line in lines:
        if "Caught up to height" in line:
            m = re.search("height ([0-9]+)", line)
            height = m.group(1)
            percent = 100.0 * (float(height) / bitcoin_block_height)
            return "Syncing... {:.2f}%".format(percent)
        elif "Waiting for chain backend to finish sync" in line:
            return "Syncing..."
        elif "Started rescan from block" in line:
            return "Scanning..."
    return "Waiting..."

def get_lnd_channels():
    try:
        macaroon = get_macaroon()
        headers = {"Grpc-Metadata-macaroon":macaroon}
        r = requests.get("https://localhost:"+LND_REST_PORT+"/v1/channels", verify=TLS_CERT_FILE,headers=headers)
        if r.status_code == 200 and r.json():
            data = r.json()
            return data["channels"]
        return False
    except Exception as e:
        print("EXCEPTION: {}".format(str(e)))
        return False

