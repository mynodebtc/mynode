from flask import Blueprint, render_template, session, abort, Markup, request, redirect
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
from bitcoin_info import *
#from bitcoin.wallet import *
from subprocess import check_output, check_call
#from electrum_functions import *
import socket
import hashlib
import json
import time

mynode_bitcoind = Blueprint('mynode_bitcoind',__name__)


### Helper functions

### Page functions
@mynode_bitcoind.route("/bitcoind")
def bitcoind_status_page():
    # Get current information
    try:
        info = get_bitcoin_blockchain_info()
        blockdata = get_bitcoin_recent_blocks()
        peerdata  = get_bitcoin_peers()
        mempooldata = get_bitcoin_mempool()
        version = get_bitcoin_version()

        # Mempool info
        mempool = {}
        mempool["size"] = "???"
        mempool["bytes"] = "0"
        if mempooldata != None:
            if "size" in mempooldata:
                mempool["size"] = mempooldata["size"]
            if "bytes" in mempooldata:
                mempool["bytes"] = mempooldata["bytes"]

        # Recent blocks
        blocks = []
        if blockdata != None:
            for b in blockdata:
                block = b
                minutes = int(time.time() - int(b["time"])) / 60
                block["age"] = "{} minutes".format(minutes)
                block["size"] = int(b["size"] / 1000)
                blocks.append(block)
            blocks.reverse()
            blocks = blocks[:5] # Take top 5

        # Peers
        peers = []
        if peerdata != None:
            for p in peerdata:
                peer = p

                if "pingtime" in p:
                    peer["pingtime"] =  int(p["pingtime"] * 1000)
                else:
                    peer["pingtime"] = "N/A"

                if "bytessent" in p:
                    peer["tx"] = "{:.2f}".format(float(p["bytessent"]) / 1000 / 1000)
                else:
                    peer["tx"] = "N/A"

                if "bytesrecv" in p:
                    peer["rx"] = "{:.2f}".format(float(p["bytesrecv"]) / 1000 / 1000)
                else:
                    peer["rx"] = "N/A"

                peers.append(peer)

    except Exception as e:
        templateData = {
            "title": "myNode Bitcoin Error",
            "message": Markup("Error communicating with bitcoind. Node may be busy syncing.<br/><br/>{}".format(str(e)))
        }
        return render_template('bitcoind_status_error.html', **templateData)


    templateData = {
        "title": "myNode Bitcoin Status",
        "blocks": blocks,
        "peers": peers,
        "difficulty": "{:.3g}".format(info["difficulty"]),
        "block_num": info["blocks"],
        "header_num": info["headers"],
        "disk_size": (int(info["size_on_disk"]) / 1000 / 1000 / 1000),
        "mempool_tx": mempool["size"],
        "mempool_size": "{:.3} MB".format(float(mempool["bytes"]) / 1000 / 1000),
        "version": version
    }
    return render_template('bitcoind_status.html', **templateData)
