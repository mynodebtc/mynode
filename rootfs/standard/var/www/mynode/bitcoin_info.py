from config import *
from utilities import *
from threading import Timer
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
bitcoin_version = None

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
        bitcoin_version = to_string(subprocess.check_output("bitcoind --version | egrep -o 'v[0-9]+\\.[0-9]+\\.[0-9]+'", shell=True))
    return bitcoin_version

def is_bitcoin_synced():
    if os.path.isfile( BITCOIN_SYNCED_FILE ):
        return True
    return False

def update_bitcoin_main_info():
    global bitcoin_block_height
    global mynode_block_height
    global bitcoin_blockchain_info

    try:
        rpc_user = get_bitcoin_rpc_username()
        rpc_pass = get_bitcoin_rpc_password()

        rpc_connection = AuthServiceProxy("http://%s:%s@127.0.0.1:8332"%(rpc_user, rpc_pass), timeout=120)

        # Basic Info
        bitcoin_blockchain_info = rpc_connection.getblockchaininfo()
        if bitcoin_blockchain_info != None:
            bitcoin_block_height = bitcoin_blockchain_info['headers']
            mynode_block_height = bitcoin_blockchain_info['blocks']

    except Exception as e:
        print("ERROR: In update_bitcoin_info - {}".format( str(e) ))
        return False

    return True

def update_bitcoin_other_info():
    global mynode_block_height
    global bitcoin_blockchain_info
    global bitcoin_recent_blocks
    global bitcoin_recent_blocks_last_cache_height
    global bitcoin_peers
    global bitcoin_network_info
    global bitcoin_mempool
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
                block_hashes = rpc_connection.batch_(commands)
                bitcoin_recent_blocks = rpc_connection.batch_([ [ "getblock", h ] for h in block_hashes ])
                bitcoin_recent_blocks_last_cache_height = mynode_block_height

            # Get peers
            bitcoin_peers = rpc_connection.getpeerinfo()

            # Get network info
            bitcoin_network_info = rpc_connection.getnetworkinfo()

            # Get mempool
            bitcoin_mempool = rpc_connection.getmempoolinfo()

            # Get wallet info
            wallets = rpc_connection.listwallets()
            wallet_data = []
            for w in wallets:
                wallet_name = urllib.pathname2url(w)
                wallet_rpc_connection = AuthServiceProxy("http://%s:%s@127.0.0.1:8332/wallet/%s"%(rpc_user, rpc_pass, wallet_name), timeout=60)
                wallet_info = wallet_rpc_connection.getwalletinfo()
                wallet_data.append(wallet_info)
            bitcoin_wallets = wallet_data
        except:
            pass

    except Exception as e:
        print("ERROR: In update_bitcoin_info - {}".format( str(e) ))
        return False

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
        return "{:.3g}".format(info["difficulty"])
    return "???"

def get_bitcoin_block_height():
    global bitcoin_block_height
    return bitcoin_block_height

def get_mynode_block_height():
    global mynode_block_height
    return mynode_block_height

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
    mempool["bytes"] = "0"
    if mempooldata != None:
        if "size" in mempooldata:
            mempool["size"] = mempooldata["size"]
        if "bytes" in mempooldata:
            mempool["bytes"] = mempooldata["bytes"]

    return copy.deepcopy(mempool)

def get_bitcoin_mempool_size():
    info = get_bitcoin_mempool_info()
    size = float(info["bytes"]) / 1000 / 1000
    return "{:.3} MB".format(size)

def get_bitcoin_wallets():
    global bitcoin_wallets
    return copy.deepcopy(bitcoin_wallets)

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

def is_bip158_enabled():
    if os.path.isfile("/mnt/hdd/mynode/settings/.bip158_enabled"):
        return True
    return False

def enable_bip158():
    touch("/mnt/hdd/mynode/settings/.bip158_enabled")

def disable_bip158():
    delete_file("/mnt/hdd/mynode/settings/.bip158_enabled")