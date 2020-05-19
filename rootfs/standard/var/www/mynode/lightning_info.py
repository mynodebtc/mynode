import copy
import requests
import subprocess
import os
import time
import re
from threading import Timer
from bitcoin_info import *
from device_info import get_journalctl_log

# Variables
lightning_info = None
lnd_ready = False
lnd_version = None
lightning_peers = None
lightning_channels = None
lightning_channel_balance = None
lightning_wallet_balance = None
lightning_desync_count = 0

LND_FOLDER = "/mnt/hdd/mynode/lnd/"
MACAROON_FILE = "/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon"
WALLET_FILE = "/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/wallet.db"
TLS_CERT_FILE = "/mnt/hdd/mynode/lnd/tls.cert"
CHANNEL_BACKUP_FILE = "/home/bitcoin/lnd_backup/channel.backup"
LND_REST_PORT = "10080"

# Functions
def update_lightning_info():
    global lightning_info
    global lightning_peers
    global lightning_channels
    global lightning_channel_balance
    global lightning_wallet_balance
    global lightning_desync_count
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
        lightning_desync_count += 1
        os.system("printf \"%s | LND De-sync!!! Count: {} \\n\" \"$(date)\" >> /tmp/lnd_failures".format(lightning_desync_count))
        if lightning_desync_count >= 8:
            os.system("printf \"%s | De-sync count too high! Retarting LND... \\n\" \"$(date)\" >> /tmp/lnd_failures")
            restart_lnd()
            lightning_desync_count = 0
        return True

    if lnd_ready:
        if lightning_desync_count > 0:
            os.system("printf \"%s | De-sync greater than 0 (was {}), but now synced! Setting to 0. \\n\" \"$(date)\" >> /tmp/lnd_failures".format(lightning_desync_count))
            lightning_desync_count = 0
        lightning_peers = lnd_get("/peers")
        lightning_channels = lnd_get("/channels")
        lightning_channel_balance = lnd_get("/balance/channels")
        lightning_wallet_balance = lnd_get("/balance/blockchain")

    return True


def get_new_deposit_address():
    address = "NEW_ADDR"
    try:
        addressdata = lnd_get("/newaddress")
        address = addressdata["address"]
    except:
        address = "ERROR"
    return address


def get_lightning_info():
    global lightning_info
    return copy.deepcopy(lightning_info)

def get_lightning_peers():
    global lightning_peers
    return copy.deepcopy(lightning_peers)

def get_lightning_channels():
    global lightning_channels
    return copy.deepcopy(lightning_channels)

def get_lightning_channel_balance():
    global lightning_channel_balance
    return copy.deepcopy(lightning_channel_balance)

def get_lightning_wallet_balance():
    global lightning_wallet_balance
    return copy.deepcopy(lightning_wallet_balance)

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
    os.system("systemctl restart lnd_admin")

def restart_lnd():
    t = Timer(1.0, restart_lnd_actual)
    t.start()

def get_macaroon():
    m = subprocess.check_output("xxd -ps -u -c 1000 "+MACAROON_FILE, shell=True)
    return m.strip()

def lnd_wallet_exists():
    return os.path.isfile(WALLET_FILE)

def create_wallet(seed):
    try:
        subprocess.check_call("create_lnd_wallet.tcl \""+seed+"\"", shell=True)
        
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

    if is_lnd_ready():
        return "Running"

    try:
        #log = subprocess.check_output("tail -n 100 /var/log/lnd.log", shell=True)
        log = get_journalctl_log("lnd")
        lines = log.splitlines()
        #lines.reverse()
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
            elif "Version: " in line:
                return "Launching..."
            elif "Opening the main database" in line:
                return "Opening DB..."
            elif "Database now open" in line:
                return "DB open..."
            elif "Waiting for wallet encryption password" in line:
                return "Logging in..."
            elif "LightningWallet opened" in line:
                return "Wallet open..."

        return "Waiting..."
    except:
        return "Status Error"

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

def get_lnd_version():
    global lnd_version
    if lnd_version == None:
        lnd_version = subprocess.check_output("lnd --version | egrep -o '[0-9]+\\.[0-9]+\\.[0-9]+' | head -n 1", shell=True)
    return lnd_version

def get_default_lnd_config():
    try:
        with open("/usr/share/mynode/lnd.conf") as f:
            return f.read()
    except:
        return "ERROR"

def get_lnd_config():
    try:
        with open("/mnt/hdd/mynode/lnd/lnd.conf") as f:
            return f.read()
    except:
        return "ERROR"

def regenerate_lnd_config():
    os.system("/usr/bin/mynode_gen_lnd_config.sh")

def get_lnd_custom_config():
    try:
        with open("/mnt/hdd/mynode/settings/lnd_custom.conf") as f:
            return f.read()
    except:
        return "ERROR"

def set_lnd_custom_config(config):
    try:
        with open("/mnt/hdd/mynode/settings/lnd_custom.conf", "w") as f:
            f.write(config)
        os.system("sync")
        return True
    except:
        return False

def delete_lnd_custom_config():
    os.system("rm -f /mnt/hdd/mynode/settings/lnd_custom.conf")