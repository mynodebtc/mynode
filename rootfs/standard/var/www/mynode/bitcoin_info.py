from config import *
from threading import Timer
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
import subprocess
import copy
import time
import os

# Variables
bitcoin_block_height = 570000
mynode_block_height = 566000
bitcoin_blockchain_info = None
bitcoin_recent_blocks = None
bitcoin_peers = []
bitcoin_wallet_info = None
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
        bitcoin_version = subprocess.check_output("bitcoind --version | egrep -o 'v[0-9]+\\.[0-9]+\\.[0-9]+'", shell=True)
    return bitcoin_version

def is_bitcoind_synced():
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
        print "ERROR: In update_bitcoin_info - {}".format( str(e) )
        return False

    return True

def update_bitcoin_other_info():
    global bitcoin_blockchain_info
    global bitcoin_recent_blocks
    global bitcoin_peers
    global bitcoin_mempool
    global bitcoin_wallet_info

    if bitcoin_blockchain_info == None:
        # We still havent gotten the important info... wait 1 minute and return
        time.sleep(60)
        return True

    try:
        rpc_user = get_bitcoin_rpc_username()
        rpc_pass = get_bitcoin_rpc_password()

        rpc_connection = AuthServiceProxy("http://%s:%s@127.0.0.1:8332"%(rpc_user, rpc_pass), timeout=60)

        # Get other less important info
        try:
            # Recent blocks
            commands = [ [ "getblockhash", height] for height in range(mynode_block_height-9, mynode_block_height+1) ]
            block_hashes = rpc_connection.batch_(commands)
            bitcoin_recent_blocks = rpc_connection.batch_([ [ "getblock", h ] for h in block_hashes ])

            # Get peers
            bitcoin_peers = rpc_connection.getpeerinfo()

            # Get mempool
            bitcoin_mempool = rpc_connection.getmempoolinfo()

            # Get wallet info
            bitcoin_wallet_info = rpc_connection.getwalletinfo()
        except:
            pass

    except Exception as e:
        print "ERROR: In update_bitcoin_info - {}".format( str(e) )
        return False

    return True

def get_bitcoin_blockchain_info():
    global bitcoin_blockchain_info
    return copy.deepcopy(bitcoin_blockchain_info)

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

def get_bitcoin_mempool():
    global bitcoin_mempool
    return copy.deepcopy(bitcoin_mempool)

def get_bitcoin_wallet_info():
    global bitcoin_wallet_info
    return copy.deepcopy(bitcoin_wallet_info)

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

def regenerate_bitcoin_config():
    os.system("/usr/bin/mynode_gen_bitcoin_config.sh")

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

def delete_bitcoin_custom_config():
    os.system("rm -f /mnt/hdd/mynode/settings/bitcoin_custom.conf")

def restart_bitcoin_actual():
    os.system("systemctl restart bitcoind")

def restart_bitcoin():
    t = Timer(1.0, restart_bitcoin_actual)
    t.start()