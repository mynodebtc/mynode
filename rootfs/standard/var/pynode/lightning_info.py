import copy
import requests
import subprocess
import os
import time
import re
import datetime
import urllib
import random
import base64
from device_info import *
from threading import Timer
from utilities import *
from bitcoin_info import *
from systemctl_info import *

# Variables
lightning_info = None
lnd_ready = False
lnd_version = None
loop_version = None
pool_version = None
lit_version = None
lightning_peers = None
lightning_peer_aliases = {}
lightning_channels = None
lightning_channel_balance = None
lightning_wallet_balance = None
lightning_transactions = None
lightning_payments = None
lightning_invoices = None
lightning_watchtower_server_info = {}
lightning_watchtower_client_towers = {}
lightning_watchtower_client_stats = {}
lightning_watchtower_client_policy = {}
lightning_desync_count = 0
lightning_update_count = 0

LIGHTNING_CACHE_FILE = "/tmp/lightning_info.json"
LND_FOLDER = "/mnt/hdd/mynode/lnd/"
TLS_CERT_FILE = "/mnt/hdd/mynode/lnd/tls.cert"
LND_REST_PORT = "10080"

# Functions
def run_lncli_command(cmd):
    try:
        base =  "lncli "
        base += "--lnddir=/mnt/hdd/mynode/lnd "
        if is_testnet_enabled():
            base += "--network=testnet "
        cmd = cmd.replace("lncli ", base)
        output = subprocess.check_output(cmd, shell=True)
        return output
    except Exception as e:
        log_message("ERROR in run_lncli_command: {}".format(str(e)))
        return None

def update_lightning_info():
    global lightning_info
    global lightning_peers
    global lightning_channels
    global lightning_channel_balance
    global lightning_wallet_balance
    global lightning_transactions
    global lightning_payments
    global lightning_invoices
    global lightning_watchtower_server_info
    global lightning_watchtower_client_towers
    global lightning_watchtower_client_stats
    global lightning_watchtower_client_policy
    global lightning_desync_count
    global lightning_update_count
    global lnd_ready

    # Check logged in
    #while not is_lnd_logged_in():
    #    lnd_ready = False
    #    time.sleep(10)

    # Get latest LN info
    lightning_info = lnd_get("/getinfo")
    lightning_update_count = lightning_update_count + 1

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
        log_message("update_lightning_info - LND READY")
        if lightning_desync_count > 0:
            os.system("printf \"%s | De-sync greater than 0 (was {}), but now synced! Setting to 0. \\n\" \"$(date)\" >> /tmp/lnd_failures".format(lightning_desync_count))
            lightning_desync_count = 0
        log_message("update_lightning_info - GET PEERS, CHANNELS, BALANCE, WALLET")
        lightning_peers = lnd_get("/peers")
        lightning_channels = lnd_get("/channels")
        lightning_channel_balance = lnd_get("/balance/channels")
        lightning_wallet_balance = lnd_get("/balance/blockchain")
        log_message("update_lightning_info - GET WATCHTOWER")
        if is_watchtower_server_enabled():
            lightning_watchtower_server_info = lnd_get_v2("/watchtower/server")
        towers = lnd_get_v2("/watchtower/client?include_sessions=1")
        log_message("update_lightning_info - TOWER DETAILS")
        tower_details = []
        if towers != None and "towers" in towers:
            for tower in towers["towers"]:
                if "pubkey" in tower and tower["active_session_candidate"]:
                    pubkey_decoded = base64.b64decode(tower['pubkey'])
                    pubkey_b16 = to_string(base64.b16encode( pubkey_decoded )).lower()
                    tower["pubkey_b16"] = pubkey_b16
                    tower_details.append(tower)
        lightning_watchtower_client_towers = tower_details
        log_message("update_lightning_info - GET CLIENT STATS, POLICY")
        lightning_watchtower_client_stats = lnd_get_v2("/watchtower/client/stats")
        lightning_watchtower_client_policy = lnd_get_v2("/watchtower/client/policy")

        # Poll slower (make sure we gather data early)
        if lightning_update_count < 30 or lightning_update_count % 2 == 0:
            log_message("update_lightning_info - GET TX INFO")
            update_lightning_tx_info()

    update_lightning_json_cache()

    return True

def update_lightning_tx_info():
    global lightning_transactions
    global lightning_payments
    global lightning_invoices
    if is_lnd_ready():
        tx_cache_limit = 50
        lightning_transactions = lnd_get("/transactions")
        lightning_payments = lnd_get("/payments", params={"reversed":"true", "index_offset": "0", "max_payments": tx_cache_limit})
        lightning_invoices = lnd_get("/invoices", params={"reversed":"true", "index_offset": "0", "num_max_invoices": tx_cache_limit})

def get_lnd_deposit_address():
    if os.path.isfile("/tmp/lnd_deposit_address"):
        addr = get_file_contents("/tmp/lnd_deposit_address")
    else:
        addr = get_new_lnd_deposit_address()
    return to_string(addr)

def get_new_lnd_deposit_address():
    address = "NEW_ADDR"
    try:
        addressdata = lnd_get("/newaddress")
        address = addressdata["address"]
        set_file_contents("/tmp/lnd_deposit_address", address)
    except:
        address = "ERROR"
    return address


def get_lightning_info():
    global lightning_info
    return copy.deepcopy(lightning_info)

def get_lightning_peers():
    global lightning_peers
    peerdata = copy.deepcopy(lightning_peers)
    peers = []
    if peerdata != None and "peers" in peerdata:
        for p in peerdata["peers"]:
            peer = p
            if "bytes_recv" in p:
                peer["bytes_recv"] = "{:.2f}".format(float(p["bytes_recv"]) / 1000 / 1000)
            else:
                peer["bytes_recv"] = "N/A"
            if "bytes_sent" in p:
                peer["bytes_sent"] = "{:.2f}".format(float(p["bytes_sent"]) / 1000 / 1000)
            else:
                peer["bytes_sent"] = "N/A"
            if "sat_sent" in p:
                if settings_file_exists("randomize_balances"):
                    peer["sat_sent"] = "0"
                else:
                    peer["sat_sent"] = format_sat_amount(peer["sat_sent"])
            if "sat_recv" in p:
                if settings_file_exists("randomize_balances"):
                    peer["sat_recv"] = "0"
                else:
                    peer["sat_recv"] = format_sat_amount(peer["sat_recv"])
            if "ping_time" not in p:
                peer["ping_time"] = "N/A"
            if "pub_key" in p:
                peer["alias"] = get_lightning_peer_alias( p["pub_key"] )
            else:
                peer["alias"] = "Unknown"
            peers.append(peer)
    return peers

def get_lightning_node_info(pubkey):
    nodeinfo = lnd_get("/graph/node/{}".format(pubkey), timeout=2)
    return nodeinfo

def get_lightning_peer_alias(pubkey):
    global lightning_peer_aliases
    if pubkey in lightning_peer_aliases:
        return lightning_peer_aliases[pubkey]

    nodeinfo = get_lightning_node_info(pubkey)
    if nodeinfo != None and "node" in nodeinfo:
        if "alias" in nodeinfo["node"]:
            lightning_peer_aliases[pubkey] = nodeinfo["node"]["alias"]
            return nodeinfo["node"]["alias"]
    return "UNKNOWN"

def get_lightning_peer_count():
    info = get_lightning_info()
    num_peers = 0
    if info != None and "num_peers" in info:
        num_peers = info['num_peers']
    return num_peers

def get_lightning_channels():
    global lightning_channels
    channeldata = copy.deepcopy(lightning_channels)
    channels = []
    if channeldata != None and "channels" in channeldata:
        for c in channeldata["channels"]:
            channel = c

            if settings_file_exists("randomize_balances"):
                c = random.randint(200000,2500000)
                p = random.random()
                channel["capacity"] = str(c)
                channel["local_balance"] = str( int(c * p) )
                channel["remote_balance"] = str( int(c * (1-p)) )
                channel["commit_fee"] = str(random.randint(1000,5000))

            channel["status_color"] = "gray"
            if "active" in channel:
                if channel["active"]:
                    channel["status_color"] = "green"
                else:
                    channel["status_color"] = "yellow"
            if "capacity" in channel:
                channel["capacity"] = format_sat_amount(channel["capacity"])
            else:
                channel["capacity"] = "N/A"
            if "local_balance" in channel and "remote_balance" in channel:
                l = float(channel["local_balance"])
                r = float(channel["remote_balance"])
                channel["chan_percent"] = (l / (l+r)) * 100
            else:
                channel["chan_percent"] = "0"
            if "local_balance" in channel:
                channel["local_balance"] = format_sat_amount(channel["local_balance"])
            else:
                channel["local_balance"] = "0"
            if "remote_balance" in channel:
                channel["remote_balance"] = format_sat_amount(channel["remote_balance"])
            else:
                channel["remote_balance"] = "0"
            if "remote_pubkey" in channel:
                channel["remote_alias"] = get_lightning_peer_alias( channel["remote_pubkey"] )
            else:
                channel["remote_alias"] = "Unknown"
            if "commit_fee" in channel:
                channel["commit_fee"] = format_sat_amount(channel["commit_fee"])
            else:
                channel["commit_fee"] = "0"
            if "lifetime" in channel:
                seconds = int(channel["lifetime"])
                channel["age"] = "{}".format(str(datetime.timedelta(seconds=seconds)))
            else:
                channel["age"] = "N/A"
            
            channels.append(channel)
    return channels

def get_lightning_channel_count():
    channels = get_lightning_channels()
    return len(channels)

def get_lightning_channel_balance():
    global lightning_channel_balance
    return copy.deepcopy(lightning_channel_balance)

def get_lightning_wallet_balance():
    global lightning_wallet_balance
    return copy.deepcopy(lightning_wallet_balance)

def get_lightning_balance_info():
    channel_balance_data = get_lightning_channel_balance()
    wallet_balance_data = get_lightning_wallet_balance()

    balance_data = {}
    balance_data["channel_balance"] = "N/A"
    balance_data["channel_pending"] = "N/A"
    balance_data["wallet_balance"] = "N/A"
    balance_data["wallet_pending"] = "N/A"
    balance_data["total_balance"] = "N/A"
    channel_num = -1
    wallet_num = -1

    channel_balance_data = get_lightning_channel_balance()
    if channel_balance_data != None and "balance" in channel_balance_data:
        balance_data["channel_balance"] = format_sat_amount( channel_balance_data["balance"] )
        channel_num = int(channel_balance_data["balance"])
    if channel_balance_data != None and "pending_open_balance" in channel_balance_data:
        balance_data["channel_pending"] = format_sat_amount( channel_balance_data["pending_open_balance"] )
    
    wallet_balance_data = get_lightning_wallet_balance()
    if wallet_balance_data != None and "confirmed_balance" in wallet_balance_data:
        balance_data["wallet_balance"] = format_sat_amount( wallet_balance_data["confirmed_balance"] )
        wallet_num = int(wallet_balance_data["confirmed_balance"])
    if wallet_balance_data != None and "unconfirmed_balance" in wallet_balance_data:
        balance_data["wallet_pending"] = format_sat_amount( wallet_balance_data["unconfirmed_balance"] )

    if channel_num >= 0 and wallet_num >= 0:
        balance_data["total_balance"] = format_sat_amount(channel_num + wallet_num)

    if settings_file_exists("randomize_balances"):
        if is_cached("randomized_channel_balance", 3600):
            channel_num = get_cached_data("randomized_channel_balance")
        else:
            channel_num = random.randint(40000,1000000)
            update_cached_data("randomized_channel_balance", channel_num)

        if is_cached("randomized_wallet_balance", 3600):
            wallet_num = get_cached_data("randomized_wallet_balance")
        else:
            wallet_num = random.randint(40000,1000000)
            update_cached_data("randomized_wallet_balance", wallet_num)

        balance_data["channel_balance"] = format_sat_amount(channel_num)
        balance_data["channel_pending"] = "0"
        balance_data["wallet_balance"] = format_sat_amount(wallet_num)
        balance_data["wallet_pending"] = "0"
        balance_data["total_balance"] = format_sat_amount(channel_num + wallet_num)

    return balance_data

def get_lightning_transactions():
    global lightning_transactions
    try:
        transactions = []
        data = copy.deepcopy(lightning_transactions)
        for tx in data["transactions"]:
            tx["id"] = tx["tx_hash"]
            if settings_file_exists("randomize_balances"):
                tx["amount_str"] = format_sat_amount(str(random.randint(-200000,500000)))
            else:
                tx["amount_str"] = format_sat_amount(tx["amount"])
            tx["date_str"] = time.strftime("%D %H:%M", time.localtime(int(tx["time_stamp"])))
            transactions.append(tx)
        return transactions
    except:
        return None

def get_lightning_payments():
    global lightning_payments
    try:
        payments = []
        data = copy.deepcopy(lightning_payments)
        for tx in data["payments"]:
            tx["id"] = tx["payment_hash"]
            tx["type"] = "PAYMENT"
            if settings_file_exists("randomize_balances"):
                tx["value_str"] = format_sat_amount( str(random.randint(1000,40000)) )
                tx["fee_str"] = format_sat_amount( str(random.randint(0,60)) )
            else:
                tx["value_str"] = format_sat_amount(tx["value_sat"])
                tx["fee_str"] = format_sat_amount(tx["fee"])
            tx["date_str"] = time.strftime("%D %H:%M", time.localtime(int(tx["creation_date"])))
            tx["memo"] = ""
            payments.append(tx)
        payments.reverse()
        return payments
    except:
        return []

def get_lightning_invoices():
    global lightning_invoices
    try:
        invoices = []
        data = copy.deepcopy(lightning_invoices)
        for tx in data["invoices"]:
            tx["id"] = tx["r_hash"]
            tx["type"] = "INVOICE"
            if settings_file_exists("randomize_balances"):
                tx["value_str"] = format_sat_amount( str(random.randint(1000,60000)) )
            else:
                tx["value_str"] = format_sat_amount(tx["value"])
            tx["date_str"] = time.strftime("%D %H:%M", time.localtime(int(tx["creation_date"])))
            tx["memo"] = unquote_plus(tx["memo"])
            invoices.append(tx)
        invoices.reverse()
        return invoices
    except:
        return []

def get_lightning_payments_and_invoices():
    payments = get_lightning_payments()
    invoices = get_lightning_invoices()
    txs = []

    if payments == None and invoices == None:
        return []
    elif payments == None and invoices != None:
        return invoices
    elif payments != None and invoices == None:
        return payments
    elif len(payments) == 0 and len(invoices) == 0:
        return []

    while len(payments) or len(invoices):
        if len(payments) == 0:
            txs.insert(0, invoices.pop())
        elif len(invoices) == 0:
            txs.insert(0, payments.pop())
        else:
            # Prepend oldest to list
            p = payments[-1]
            i = invoices[-1]
            if int(p["creation_date"]) < int(i["creation_date"]):
                txs.insert(0, payments.pop())
            else:
                txs.insert(0, invoices.pop())

    for tx in txs:
        if tx["type"] == "PAYMENT":
            tx["value_str"] = "-" + tx["value_str"]

    return txs

def get_lightning_watchtower_server_info():
    global lightning_watchtower_server_info
    server_info = copy.deepcopy(lightning_watchtower_server_info)
    server_info["watchtower_server_uri"] = "..."

    if server_info != None:
        try:
            if "uris" in server_info and len(server_info['uris']) > 0:
                first_uri = True
                text = ""
                for uri in server_info['uris']:
                    if first_uri:
                        first_uri = False
                    else:
                        text += "<br/>"
                    text += uri
                server_info["watchtower_server_uri"] = text
            elif "pubkey" in server_info or "listeners" in server_info:
                server_info["watchtower_server_uri"] = ""
                if "pubkey" in server_info:
                    pubkey_decoded = base64.b64decode(server_info['pubkey'])
                    pubkey_b16 = to_string(base64.b16encode( pubkey_decoded )).lower()
                    server_info["watchtower_server_uri"] += pubkey_b16
                #if "listeners":
                #    server_info["watchtower_server_uri"] += "listeners: " + watchtower_server_info["listeners"][0]
        except:
            return server_info

    return server_info

def get_lightning_watchtower_client_towers():
    global lightning_watchtower_client_towers
    towers = copy.deepcopy(lightning_watchtower_client_towers)
    return towers

def get_lightning_watchtower_client_stats():
    global lightning_watchtower_client_stats
    stats = copy.deepcopy(lightning_watchtower_client_stats)
    return stats

def get_lightning_watchtower_client_policy():
    global lightning_watchtower_client_policy
    policy = copy.deepcopy(lightning_watchtower_client_policy)
    return policy

def is_lnd_ready():
    global lnd_ready
    return lnd_ready

def lnd_get(path, timeout=10, params={}):
    try:
        macaroon = get_macaroon()
        headers = {"Grpc-Metadata-macaroon":macaroon}
        r = requests.get("https://localhost:"+LND_REST_PORT+"/v1"+path, verify=TLS_CERT_FILE,headers=headers, params=params, timeout=timeout)
    except Exception as e:
        log_message("ERROR in lnd_get: "+str(e))
        return {"error": str(e)}
    return r.json()

def lnd_get_v2(path, timeout=10):
    try:
        macaroon = get_macaroon()
        headers = {'Grpc-Metadata-macaroon': macaroon}
        r = requests.get("https://localhost:"+LND_REST_PORT+"/v2"+path, verify=TLS_CERT_FILE, headers=headers, timeout=timeout)
    except Exception as e:
        log_message("ERROR in lnd_get_v2: "+str(e))
        return {"error": str(e)}
    return r.json()

def gen_new_wallet_seed():
    seed = to_string(subprocess.check_output("python3 /usr/bin/gen_seed.py", shell=True))
    return seed

def get_lnd_lit_password():
    return to_string( get_file_contents("/mnt/hdd/mynode/settings/.litpw") )

def restart_lnd_actual():
    global lnd_ready
    lnd_ready = False
    os.system("systemctl restart lnd")
    os.system("systemctl restart lnd_admin")

def restart_lnd():
    t = Timer(0.1, restart_lnd_actual)
    t.start()

    time.sleep(1)

def get_lightning_wallet_file():
    if is_testnet_enabled():
        return "/mnt/hdd/mynode/lnd/data/chain/bitcoin/testnet/wallet.db"
    return "/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/wallet.db"

def get_lightning_macaroon_file():
    if is_testnet_enabled():
        return "/mnt/hdd/mynode/lnd/data/chain/bitcoin/testnet/admin.macaroon"
    return "/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon"

def get_macaroon():
    m = to_string(subprocess.check_output("xxd -ps -u -c 1000 " + get_lightning_macaroon_file(), shell=True))
    return m.strip()

def lnd_wallet_exists():
    return os.path.isfile( get_lightning_wallet_file() )

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

def get_lnd_channel_backup_file():
    if is_testnet_enabled():
        return "/home/bitcoin/lnd_backup/channel_testnet.backup"
    return "/home/bitcoin/lnd_backup/channel.backup"

def lnd_channel_backup_exists():
    return os.path.isfile( get_lnd_channel_backup_file() )

def lnd_get_channel_db_size():
    path = "mainnet"
    if is_testnet_enabled():
        path = "testnet"
    size = "???"
    try:
        size = to_string(subprocess.check_output("ls -lsah /mnt/hdd/mynode/lnd/data/graph/"+path+"/channel.db | awk '{print $6}'", shell=True))
    except:
        size = "ERR"
    return size

def get_lnd_status():
    #if not lnd_wallet_exists():
    #    return "Please create wallet..."

    if not is_bitcoin_synced():
        return "Waiting..."

    if is_lnd_ready():
        return "Running"

    try:
        log = get_journalctl_log("lnd")
        lines = log.splitlines()
        for line in lines:
            if "Waiting for wallet encryption password" in line and not lnd_wallet_exists():
                return "Please create wallet..."
            elif "Caught up to height" in line:
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
            elif "unable to create server" in line:
                return "Network Error"
            elif "Waiting for wallet encryption password" in line:
                return "Logging in..."
            elif "LightningWallet opened" in line:
                return "Wallet open..."
            elif "wallet unlock password file was specified but wallet does not exist" in line:
                return "Config Error"

        # Check if no wallet file (log may have been rotated out, so can't get more accurate message)
        if not lnd_wallet_exists():
            return "Please create wallet..."

        return "Waiting..."
    except:
        return "Status Error"

def get_lnd_status_color():
    if not is_bitcoin_synced():
        return "yellow"

    #if not lnd_wallet_exists():
    #    # This hides the restart /login attempt LND does from the GUI
    #    return "green"
    
    lnd_status_code = get_service_status_code("lnd")
    if lnd_status_code != 0:
        lnd_status_color = "red"
        lnd_status = get_lnd_status()
        if lnd_status == "Logging in...":
            lnd_status_color = "yellow"
        return lnd_status_color
    return "green"

def get_lnd_version():
    global lnd_version
    if lnd_version == None:
        lnd_version = to_string(subprocess.check_output("lnd --version | egrep -o '[0-9]+\\.[0-9]+\\.[0-9]+' | head -n 1", shell=True))
    return "v{}".format(lnd_version)

def get_loop_version():
    global loop_version
    if loop_version == None:
        loop_version = to_string(subprocess.check_output("loopd --version | egrep -o '[0-9]+\\.[0-9]+\\.[0-9]+' | head -n 1", shell=True))
    return "v{}".format(loop_version)

def get_pool_version():
    global pool_version
    if pool_version == None:
        pool_version = to_string(subprocess.check_output("poold --version | egrep -o '[0-9]+\\.[0-9]+\\.[0-9]+' | head -n 1", shell=True))
    return "v{}".format(pool_version)

def get_lit_version():
    global lit_version
    if lit_version == None:
        #lit_version = to_string(subprocess.check_output("litd --version | egrep -o '[0-9]+\\.[0-9]+\\.[0-9]+' | head -n 1", shell=True))
        lit_version = "TODO"
    return "v{}".format(lit_version)

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

def using_lnd_custom_config():
    return os.path.isfile("/mnt/hdd/mynode/settings/lnd_custom.conf")

def delete_lnd_custom_config():
    os.system("rm -f /mnt/hdd/mynode/settings/lnd_custom.conf")

def get_lnd_alias_file_data():
    try:
        with open("/mnt/hdd/mynode/settings/.lndalias", "r") as f:
            return f.read().strip()
    except:
        return "ERROR"
    return "ERROR"

def is_watchtower_server_enabled():
    return settings_file_exists("watchtower_enabled")

def enable_watchtower_server():
    create_settings_file("watchtower_enabled")

def disable_watchtower_server():
    delete_settings_file("watchtower_enabled")


def is_watchtower_client_enabled():
    return settings_file_exists("watchtower_client_enabled")

def enable_watchtower_client():
    create_settings_file("watchtower_client_enabled")

def disable_watchtower_client():
    delete_settings_file("watchtower_client_enabled")

# Only call from www process which has data
def update_lightning_json_cache():
    global LIGHTNING_CACHE_FILE
    lightning_data = {}
    lightning_data["info"] = get_lightning_info()
    lightning_data["peers"] = get_lightning_peers()
    lightning_data["channels"] = get_lightning_channels()
    lightning_data["balances"] = get_lightning_balance_info()
    #lightning_data["transactions"] = lightning_transactions
    #lightning_data["payments"] = lightning_payments
    #lightning_data["invoices"] = lightning_invoices
    #lightning_data["watchtower_server_info"] = lightning_watchtower_server_info
    return set_dictionary_file_cache(lightning_data, LIGHTNING_CACHE_FILE)

# Can call from any process
def get_lightning_json_cache():
    global LIGHTNING_CACHE_FILE
    return get_dictionary_file_cache(LIGHTNING_CACHE_FILE)