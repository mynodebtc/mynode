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
BITCOIN_CACHE_FILE = "/tmp/bitcoin_info.json"

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

def update_bitcoin_main_info():
    global bitcoin_block_height
    global mynode_block_height
    global bitcoin_blockchain_info

    try:
        rpc_user = get_bitcoin_rpc_username()
        rpc_pass = get_bitcoin_rpc_password()

        rpc_connection = AuthServiceProxy("http://%s:%s@127.0.0.1:8332"%(rpc_user, rpc_pass), timeout=120)

        # Basic Info
        info = rpc_connection.getblockchaininfo()
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
                    block_hashes = rpc_connection.batch_(commands)
                    bitcoin_recent_blocks = rpc_connection.batch_([ [ "getblock", h ] for h in block_hashes ])
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
                log_message("{} comparing to {}".format(new_wallet, w["walletname"]))
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

def get_bitcoin_extra_config():
    try:
        if not os.path.isfile("/mnt/hdd/mynode/settings/bitcoin_extra_config.conf"):
            return ""
        with open("/mnt/hdd/mynode/settings/bitcoin_extra_config.conf") as f:
            return f.read()
    except:
        return "ERROR"

def set_bitcoin_extra_config(config):
    try:
        with open("/mnt/hdd/mynode/settings/bitcoin_extra_config.conf", "w") as f:
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