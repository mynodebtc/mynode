from config import *
from utilities import *
from systemctl_info import *
from threading import Timer
import requests
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
import urllib
import subprocess
import copy
import time
import os
import re

# Variables
bitcoin_block_height = 570000
mynode_block_height = 566000
bitcoin_blockchain_info = None
bitcoin_recent_blocks = None
bitcoin_recent_blocks_last_cache_height = 566000
bitcoin_peers = []
bitcoin_network_info = None
bitcoin_wallets = None
bitcoin_mempool = None
bitcoin_recommended_fees = None
bitcoin_version = None
bitcoin_connection_count = None
bitcoin_sync_status = None
header_tip_time_cache = {"height": None, "time": None}
BITCOIN_CACHE_FILE = "/tmp/bitcoin_info.json"

# Header sync progress lines written to debug.log by bitcoind (pre-sync was added in Bitcoin Core v24)
HEADER_PRESYNC_REGEX = re.compile(r"Pre-synchronizing blockheaders, height: (\d+) \(~([\d.]+)%\)")
HEADER_SYNC_REGEX = re.compile(r"Synchronizing blockheaders, height: (\d+) \(~([\d.]+)%\)")
BITCOIN_STARTUP_REGEX = re.compile(r"Bitcoin \w+ version v")
LOG_TAIL_BYTES = 256 * 1024

# Functions
def get_bitcoin_rpc_username():
    return "mynode"

def get_bitcoin_rpc_password():
    try:
        with open("/mnt/hdd/mynode/settings/.btcrpcpw", "r") as f:
            return f.read()
    except:
        return "error_getting_password"

def get_bitcoin_version():
    global bitcoin_version
    if bitcoin_version == None:
        try:
            bitcoin_version = to_string(subprocess.check_output("bitcoind --version | egrep -o 'v[0-9]+\\.[0-9]+\\.[a-z0-9]+'", shell=True))
        except Exception as e:
            bitcoin_version = "unknown"
    return bitcoin_version

def is_bitcoin_synced():
    if os.path.isfile( BITCOIN_SYNCED_FILE ):
        return True
    return False

def run_bitcoincli_command(cmd):
    cmd = "bitcoin-cli --conf=/mnt/hdd/mynode/bitcoin/bitcoin.conf --datadir=/mnt/hdd/mynode/bitcoin "+cmd+"; exit 0"
    log_message("Running bitcoin-cli cmd:  {}".format(cmd))
    try:
        results = to_string(subprocess.check_output(cmd, stderr=subprocess.STDOUT, shell=True))
    except Exception as e:
        results = str(e)
    return results

def get_bitcoin_debug_log_file():
    if os.path.isfile("/mnt/hdd/mynode/settings/.testnet_enabled"):
        return "/mnt/hdd/mynode/bitcoin/testnet3/debug.log"
    return "/mnt/hdd/mynode/bitcoin/debug.log"

def read_header_sync_from_log():
    # Find the most recent header sync line logged since bitcoind last started
    try:
        with open(get_bitcoin_debug_log_file(), "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - LOG_TAIL_BYTES))
            data = f.read().decode("utf-8", "ignore")
    except Exception:
        return None
    for line in reversed(data.splitlines()):
        m = HEADER_PRESYNC_REGEX.search(line)
        if m:
            return {"presync": True, "height": int(m.group(1)), "percent": float(m.group(2))}
        m = HEADER_SYNC_REGEX.search(line)
        if m:
            return {"presync": False, "height": int(m.group(1)), "percent": float(m.group(2))}
        if BITCOIN_STARTUP_REGEX.search(line):
            break
    return None

def get_header_tip_time(rpc_connection, header_height):
    # Block time of the best header, cached by height so it is only looked up when the header tip moves
    global header_tip_time_cache
    if header_tip_time_cache["height"] == header_height:
        return header_tip_time_cache["time"]
    for tip in rpc_connection.getchaintips():
        if tip["height"] == header_height and tip["status"] in ["active", "valid-fork", "valid-headers", "headers-only"]:
            header = rpc_connection.getblockheader(tip["hash"])
            header_tip_time_cache = {"height": header_height, "time": int(header["time"])}
            return header_tip_time_cache["time"]
    return None

def calculate_bitcoin_sync_status(info, peer_count, header_tip_time, log_status):
    status = {}
    status["running"] = info != None
    status["peers"] = peer_count
    status["blocks"] = 0
    status["headers"] = 0
    status["block_percent"] = 0.0
    status["header_percent"] = None
    status["presync_active"] = False
    status["presync_height"] = 0
    status["presync_percent"] = 0.0
    status["headers_synced"] = False
    status["blocks_synced"] = False
    status["stage"] = "starting"
    if info == None:
        return status

    status["blocks"] = info["blocks"]
    status["headers"] = info["headers"]
    status["block_percent"] = float(info.get("verificationprogress", 0)) * 100
    in_ibd = info.get("initialblockdownload", True)

    # Headers are not stored during pre-sync, so the header count stays behind the pre-sync height
    if in_ibd and log_status != None and log_status["presync"] and log_status["height"] > status["headers"]:
        status["presync_active"] = True
        status["presync_height"] = log_status["height"]
        status["presync_percent"] = log_status["percent"]

    # Headers are caught up once the header tip is within a day of now (same estimate bitcoind uses)
    if not in_ibd:
        status["headers_synced"] = True
    elif status["presync_active"]:
        status["headers_synced"] = False
    elif header_tip_time != None:
        blocks_left = max(0, int(time.time()) - header_tip_time) / 600.0
        total = status["headers"] + blocks_left
        if total > 0:
            status["header_percent"] = 100.0 * status["headers"] / total
        status["headers_synced"] = blocks_left < 144
    elif log_status != None and not log_status["presync"] and log_status["height"] >= status["headers"]:
        status["header_percent"] = log_status["percent"]
        status["headers_synced"] = log_status["percent"] >= 99.9
    else:
        status["headers_synced"] = status["headers"] > 0 and status["blocks"] > 0
    if status["headers_synced"]:
        status["header_percent"] = 100.0

    status["blocks_synced"] = status["headers_synced"] and status["blocks"] >= status["headers"]
    if status["blocks_synced"]:
        status["block_percent"] = 100.0

    if status["presync_active"]:
        status["stage"] = "presync_headers"
    elif status["headers"] == 0 and not status["headers_synced"]:
        status["stage"] = "starting"
    elif not status["headers_synced"]:
        status["stage"] = "sync_headers"
    elif not status["blocks_synced"]:
        status["stage"] = "sync_blocks"
    else:
        status["stage"] = "synced"
    return status

def update_bitcoin_main_info():
    global bitcoin_block_height
    global mynode_block_height
    global bitcoin_blockchain_info
    global bitcoin_connection_count
    global bitcoin_sync_status

    info = None
    try:
        rpc_user = get_bitcoin_rpc_username()
        rpc_pass = get_bitcoin_rpc_password()

        rpc_connection = AuthServiceProxy("http://%s:%s@127.0.0.1:8332"%(rpc_user, rpc_pass), timeout=120)

        # Basic Info
        info = rpc_connection.getblockchaininfo()

        # Sync progress info (uses the raw info, before the data cleanup below)
        try:
            bitcoin_connection_count = rpc_connection.getconnectioncount()
        except Exception:
            bitcoin_connection_count = None
        header_tip_time = None
        log_status = None
        if info != None and info.get("initialblockdownload", True):
            try:
                header_tip_time = get_header_tip_time(rpc_connection, info["headers"])
            except Exception:
                header_tip_time = None
            # The log is only needed while headers are behind (pre-sync, or no header tip time)
            if header_tip_time == None or int(time.time()) - header_tip_time > 600 * 144:
                log_status = read_header_sync_from_log()
        bitcoin_sync_status = calculate_bitcoin_sync_status(info, bitcoin_connection_count, header_tip_time, log_status)

        if info != None:
            # Save specific data
            bitcoin_block_height = info['headers']
            mynode_block_height = info['blocks']
            # Data cleanup
            if "difficulty" in info:
                info["difficulty"] = "{:.3g}".format(info["difficulty"])
            if "verificationprogress" in info:
                info["verificationprogress"] = "{:.2f}%".format(100 * info["verificationprogress"])
            else:
                info["verificationprogress"] = "???"

        bitcoin_blockchain_info = info

    except Exception as e:
        log_message("ERROR: In update_bitcoin_info - {} DATA: {}".format( str(e), str(info) ))
        bitcoin_sync_status = calculate_bitcoin_sync_status(None, None, None, None)
        return False

    update_bitcoin_json_cache()
    return True

def update_bitcoin_other_info():
    global mynode_block_height
    global bitcoin_blockchain_info
    global bitcoin_recent_blocks
    global bitcoin_recent_blocks_last_cache_height
    global bitcoin_peers
    global bitcoin_network_info
    global bitcoin_mempool
    global bitcoin_recommended_fees
    global bitcoin_wallets

    while bitcoin_blockchain_info == None:
        # Wait until we have gotten the important info...
        # Checking quickly helps the API get started faster
        time.sleep(1)

    try:
        rpc_user = get_bitcoin_rpc_username()
        rpc_pass = get_bitcoin_rpc_password()

        rpc_connection = AuthServiceProxy("http://%s:%s@127.0.0.1:8332"%(rpc_user, rpc_pass), timeout=60)

        # Get other less important info
        try:
            # Recent blocks
            if mynode_block_height != bitcoin_recent_blocks_last_cache_height:
                commands = [ [ "getblockhash", height] for height in range(mynode_block_height-9, mynode_block_height+1) ]
                try:
                    block_hashes = [rpc_connection.getblockhash(cmd[1]) for cmd in commands]
                    bitcoin_recent_blocks = [rpc_connection.getblock(h) for h in block_hashes]
                    bitcoin_recent_blocks_last_cache_height = mynode_block_height
                except Exception as e_block:
                    log_message("ERROR: getblockhash batch command failure " + str(e_block))

            # Get peers and cleanup data
            log_message("update_bitcoin_other_info - PEERS")
            peerdata = rpc_connection.getpeerinfo()
            peers = []
            if peerdata != None:
                for p in peerdata:
                    peer = p

                    peer["pingtime"] = int(float(p["pingtime"])*1000) if ("pingtime" in p) else "N/A"
                    peer["tx"] = "{:.2f}".format(float(p["bytessent"]) / 1000 / 1000) if ("bytessent" in p) else "N/A"
                    peer["rx"] = "{:.2f}".format(float(p["bytesrecv"]) / 1000 / 1000) if ("bytesrecv" in p) else "N/A"
                    peer["minping"] = str(p["minping"]) if ("minping" in p) else "N/A"
                    peer["minfeefilter"] = str(p["minfeefilter"]) if ("minfeefilter" in p) else "N/A"
                    peer["pingwait"] = str(p["pingwait"]) if ("pingwait" in p) else "N/A"

                    peers.append(peer)
            bitcoin_peers = peers

            # Get network info
            log_message("update_bitcoin_other_info - NETWORK")
            network_data = rpc_connection.getnetworkinfo()
            if network_data != None:
                network_data["relayfee"] = str(network_data["relayfee"])
                network_data["incrementalfee"] = str(network_data["incrementalfee"])
            bitcoin_network_info = network_data

            # Get mempool
            log_message("update_bitcoin_other_info - MEMPOOL")
            mempool_data = rpc_connection.getmempoolinfo()
            if mempool_data != None:
                mempool_data["total_fee"] = str(mempool_data["total_fee"])
                mempool_data["mempoolminfee"] = str(mempool_data["mempoolminfee"])
                mempool_data["minrelaytxfee"] = str(mempool_data["minrelaytxfee"])
            bitcoin_mempool = mempool_data

            # Get wallet info
            log_message("update_bitcoin_other_info - WALLETS")
            wallets = rpc_connection.listwallets()
            wallet_data = []
            for w in wallets:
                wallet_name = "FILL_IN"
                if isPython3():
                    wallet_name = urllib.request.pathname2url(w)
                else:
                    wallet_name = urllib.pathname2url(w)

                wallet_rpc_connection = AuthServiceProxy("http://%s:%s@127.0.0.1:8332/wallet/%s"%(rpc_user, rpc_pass, wallet_name), timeout=60)
                wallet_info = wallet_rpc_connection.getwalletinfo()
                wallet_info["can_delete"] = True
                if wallet_name == "wallet.dat":
                    wallet_info["can_delete"] = False
                wallet_data.append(wallet_info)
            bitcoin_wallets = wallet_data
            create_default_wallets()

            # Get recommended fee info (from mempool on port 4080)
            log_message("update_bitcoin_other_info - MEMPOOL")
            if is_service_enabled("mempool"):
                try:
                    r = requests.get("http://localhost:4080/api/v1/fees/recommended", timeout=1)
                    data = r.json()
                    bitcoin_recommended_fees = ""
                    bitcoin_recommended_fees += "Low priority: {} sat/vB".format(data["hourFee"])
                    bitcoin_recommended_fees += " &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; "
                    bitcoin_recommended_fees += "Medium priority: {} sat/vB".format(data["halfHourFee"])
                    bitcoin_recommended_fees += " &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; "
                    bitcoin_recommended_fees += "High priority: {} sat/vB".format(data["fastestFee"])
                except Exception as e:
                    bitcoin_recommended_fees = "Fee error - " . str(e)
            else:
                bitcoin_recommended_fees = None
        except Exception as e1:
            log_message("ERROR: In update_bitcoin_other_info (1) - {} DATA: {}".format( str(e1), str() ))

    except Exception as e2:
        log_message("ERROR: In update_bitcoin_other_info (2) - {} DATA: {}".format( str(e2), str() ))
        return False

    update_bitcoin_json_cache()
    return True

def get_bitcoin_status():
    height = get_bitcoin_block_height()
    block = get_mynode_block_height()
    status = "unknown"

    if height != None and block != None:
        remaining = height - block
        if remaining == 0:
            status = "Running"
        else:
            status = "Syncing<br/>{} blocks remaining...".format(remaining)
    else:
        status = "Waiting for info..."
    return status

def get_bitcoin_blockchain_info():
    global bitcoin_blockchain_info
    return copy.deepcopy(bitcoin_blockchain_info)

def get_bitcoin_difficulty():
    info = get_bitcoin_blockchain_info()
    if "difficulty" in info:
        return info["difficulty"]
    return "???"

def get_bitcoin_block_height():
    global bitcoin_block_height
    return bitcoin_block_height

def get_mynode_block_height():
    global mynode_block_height
    return mynode_block_height

def get_bitcoin_sync_progress():
    info = get_bitcoin_blockchain_info()
    progress = "???"
    if info:
        if "verificationprogress" in info:
            return info["verificationprogress"]
    return progress

def get_bitcoin_sync_status():
    global bitcoin_sync_status
    return copy.deepcopy(bitcoin_sync_status)

def get_bitcoin_sync_display():
    # Text and the current stage (if any) for the sync page
    status = get_bitcoin_sync_status()
    if status == None:
        status = calculate_bitcoin_sync_status(None, None, None, None)

    display = {}
    display["stage"] = status["stage"]
    display["peers"] = "{:,}".format(status["peers"]) if status["peers"] != None else "..."
    display["no_peers"] = status["peers"] == 0
    display["marked_synced"] = is_bitcoin_synced()
    display["step"] = None

    if not status["running"]:
        display["stage_text"] = "Waiting for Bitcoin to start..."
    elif status["stage"] == "starting":
        display["stage_text"] = "Connecting to peers..." if display["no_peers"] else "Waiting for block headers..."
    elif status["stage"] == "synced":
        display["stage_text"] = "Synchronized! Starting services..."
    else:
        display["stage_text"] = "Syncing..."

    step = None
    if status["stage"] == "presync_headers":
        step = {"number": 1, "name": "Pre-synchronizing Headers", "percent": status["presync_percent"]}
        step["detail"] = "Height {:,} (~{:.2f}%)".format(status["presync_height"], step["percent"])
    elif status["stage"] == "sync_headers":
        step = {"number": 2, "name": "Synchronizing Headers", "percent": status["header_percent"]}
        if step["percent"] != None:
            step["detail"] = "Height {:,} (~{:.2f}%)".format(status["headers"], step["percent"])
        else:
            step["detail"] = "Height {:,}".format(status["headers"])
    elif status["stage"] == "sync_blocks":
        step = {"number": 3, "name": "Synchronizing Blocks", "percent": status["block_percent"]}
        step["detail"] = "Block {:,} of {:,} (~{:.2f}%)".format(status["blocks"], status["headers"], step["percent"])
    if step != None:
        step["count"] = 3
        step["percent"] = min(100.0, max(0.0, step["percent"] or 0.0))
        step["percent_str"] = "{:.2f}".format(step["percent"])
        display["step"] = step
    return display

def get_bitcoin_recent_blocks():
    global bitcoin_recent_blocks
    return copy.deepcopy(bitcoin_recent_blocks)

def get_bitcoin_peers():
    global bitcoin_peers
    return copy.deepcopy(bitcoin_peers)

def get_bitcoin_peer_count():
    peers = get_bitcoin_peers()
    if peers != None:
        return len(peers)
    return 0

def get_bitcoin_network_info():
    global bitcoin_network_info
    return copy.deepcopy(bitcoin_network_info)

def get_bitcoin_mempool():
    global bitcoin_mempool
    return copy.deepcopy(bitcoin_mempool)

def get_bitcoin_mempool_info():
    mempooldata = get_bitcoin_mempool()

    mempool = {}
    mempool["size"] = "???"
    mempool["count"] = "???"
    mempool["bytes"] = "0"
    mempool["display_bytes"] = "???"
    if mempooldata != None:
        mempool["display_size"] = "unknown"
        if "size" in mempooldata:
            mempool["size"] = mempooldata["size"]
            mempool["count"] = mempooldata["size"]
        if "bytes" in mempooldata:
            mempool["bytes"] = mempooldata["bytes"]
            mb = round(float(mempool["bytes"] / 1000 / 1000), 2)
            mempool["display_bytes"] = "{0:.10} MB".format( mb )

    return copy.deepcopy(mempool)

def get_bitcoin_disk_usage():
    info = get_bitcoin_blockchain_info()
    if "size_on_disk" in info:
        usage = int(info["size_on_disk"]) / 1000 / 1000 / 1000
        return "{:.0f}".format(usage)
    else:
        return "UNK"

def get_bitcoin_recommended_fees():
    global bitcoin_recommended_fees
    return bitcoin_recommended_fees

def get_bitcoin_wallets():
    global bitcoin_wallets
    return copy.deepcopy(bitcoin_wallets)

def create_default_wallets():
    default_wallets = ["joinmarket_wallet.dat"]
    if is_bitcoin_synced():
        wallets = get_bitcoin_wallets()
        for new_wallet in default_wallets:
            found = False
            for w in wallets:
                if new_wallet == w["walletname"]:
                    found = True
                    break
            if not found:
                log_message("Creating new default wallet {}".format(new_wallet))
                run_bitcoincli_command("-named createwallet wallet_name={} descriptors=false".format(new_wallet))
                run_bitcoincli_command("loadwallet {}".format(new_wallet))


def get_default_bitcoin_config():
    try:
        with open("/usr/share/mynode/bitcoin.conf") as f:
            return f.read()
    except:
        return "ERROR"

def get_bitcoin_config():
    try:
        with open("/mnt/hdd/mynode/bitcoin/bitcoin.conf") as f:
            return f.read()
    except:
        return "ERROR"

def get_bitcoin_pre_config():
    try:
        if not os.path.isfile("/mnt/hdd/mynode/settings/bitcoin_pre_config.conf"):
            return ""
        with open("/mnt/hdd/mynode/settings/bitcoin_pre_config.conf") as f:
            return f.read()
    except:
        return "ERROR"

def set_bitcoin_pre_config(config):
    try:
        with open("/mnt/hdd/mynode/settings/bitcoin_pre_config.conf", "w") as f:
            f.write(config)
        os.system("sync")
        return True
    except:
        return False
    
def get_bitcoin_post_config():
    try:
        if not os.path.isfile("/mnt/hdd/mynode/settings/bitcoin_post_config.conf"):
            return ""
        with open("/mnt/hdd/mynode/settings/bitcoin_post_config.conf") as f:
            return f.read()
    except:
        return "ERROR"

def set_bitcoin_post_config(config):
    try:
        with open("/mnt/hdd/mynode/settings/bitcoin_post_config.conf", "w") as f:
            f.write(config)
        os.system("sync")
        return True
    except:
        return False

def get_bitcoin_custom_config():
    try:
        with open("/mnt/hdd/mynode/settings/bitcoin_custom.conf") as f:
            return f.read()
    except:
        return "ERROR"

def set_bitcoin_custom_config(config):
    try:
        with open("/mnt/hdd/mynode/settings/bitcoin_custom.conf", "w") as f:
            f.write(config)
        os.system("sync")
        return True
    except:
        return False

def using_bitcoin_custom_config():
    return os.path.isfile("/mnt/hdd/mynode/settings/bitcoin_custom.conf")

def delete_bitcoin_custom_config():
    os.system("rm -f /mnt/hdd/mynode/settings/bitcoin_custom.conf")

def get_custom_bitcoin_version():
    # Returns the custom Bitcoin version the user selected (ex: knots_autoupdate)
    # or an empty string when the default version of Bitcoin is being used.
    files = ["/home/bitcoin/.mynode/custom_bitcoin_selection",
             "/mnt/hdd/mynode/settings/custom_bitcoin_selection",
             # Older installs may not have a selection file, so fall back to the installed custom version
             "/home/bitcoin/.mynode/bitcoin_version_latest_custom",
             "/mnt/hdd/mynode/settings/bitcoin_version_latest_custom"]
    for filename in files:
        if os.path.isfile(filename):
            version = to_string(get_file_contents(filename))
            if version != "" and version != "ERROR":
                return version
    return ""

def restart_bitcoin_actual():
    os.system("systemctl restart bitcoin")

def restart_bitcoin():
    t = Timer(1.0, restart_bitcoin_actual)
    t.start()

def is_bip37_enabled():
    if os.path.isfile("/mnt/hdd/mynode/settings/.bip37_enabled"):
        return True
    return False
def enable_bip37():
    touch("/mnt/hdd/mynode/settings/.bip37_enabled")
def disable_bip37():
    delete_file("/mnt/hdd/mynode/settings/.bip37_enabled")

def is_bip157_enabled():
    if os.path.isfile("/mnt/hdd/mynode/settings/.bip157_enabled"):
        return True
    return False
def enable_bip157():
    touch("/mnt/hdd/mynode/settings/.bip157_enabled")
def disable_bip157():
    delete_file("/mnt/hdd/mynode/settings/.bip157_enabled")

def is_bip158_enabled():
    if os.path.isfile("/mnt/hdd/mynode/settings/.bip158_enabled"):
        return True
    return False
def enable_bip158():
    touch("/mnt/hdd/mynode/settings/.bip158_enabled")
def disable_bip158():
    delete_file("/mnt/hdd/mynode/settings/.bip158_enabled")


def update_bitcoin_json_cache():
    global BITCOIN_CACHE_FILE
    bitcoin_data = {}
    bitcoin_data["version"] = get_bitcoin_version()
    bitcoin_data["current_block_height"] = mynode_block_height
    bitcoin_data["blockchain_info"] = get_bitcoin_blockchain_info()
    #bitcoin_data["recent_blocks"] = bitcoin_recent_blocks
    bitcoin_data["peers"] = get_bitcoin_peers()
    bitcoin_data["network_info"] = get_bitcoin_network_info()
    bitcoin_data["mempool"] = get_bitcoin_mempool_info()
    #bitcoin_data["recommended_fees"] = bitcoin_recommended_fees
    bitcoin_data["disk_usage"] = get_bitcoin_disk_usage()
    return set_dictionary_file_cache(bitcoin_data, BITCOIN_CACHE_FILE)

def get_bitcoin_json_cache():
    global BITCOIN_CACHE_FILE
    return get_dictionary_file_cache(BITCOIN_CACHE_FILE)