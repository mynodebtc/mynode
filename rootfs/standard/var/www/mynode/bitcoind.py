from flask import Blueprint, render_template, session, abort, Markup, request, redirect
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
from bitcoin_info import *
#from bitcoin.wallet import *
from subprocess import check_output, check_call
from electrum_functions import *
import socket
import hashlib
import json
import time

mynode_bitcoind = Blueprint('mynode_bitcoind',__name__)


### Helper functions
def reverse_hash(btchash):
    rev = ""
    pair = ""
    for c in btchash[::-1]:
        pair = c + pair
        if len(pair) == 2:
            rev += pair
            pair = ""
    return rev

def get_scripthash_for_address(addr):
    if addr.isalnum():
        try:
            ret = check_output(["/usr/bin/get_scripthash.py",addr])
            return ret.strip()
        except:
            raise Exception( "{} is not a valid BTC address!".format(addr) )
    raise Exception('Invalid BTC Address!')

def is_bitcoin_address(addr):
    if addr.isalnum():
        try:
            check_call(["/usr/bin/get_scripthash.py",addr])
            return True
        except:
            return False
    raise Exception('Invalid BTC Address!')

def search(search_term):
    try:
        rpc_user = get_bitcoin_rpc_username()
        rpc_pass = get_bitcoin_rpc_password()
        rpc_connection = AuthServiceProxy("http://%s:%s@127.0.0.1:8332"%(rpc_user, rpc_pass), timeout=10)
        results = {}
        results["type"] = "not_found"
        results["id"] = ""
        search_term = search_term.strip()

        # Try to get a block (by height)
        try:
            if (search_term.isdigit()):
                blockhash = rpc_connection.getblockhash(int(search_term))
                results["type"] = "block"
                results["id"] = blockhash
                return results
        except JSONRPCException as e:
            pass

        # Try to get address
        try:
            if is_bitcoin_address(search_term):
                results["type"] = "addr"
                results["id"] = search_term
            return results
        except:
            pass

        # Try to get a block (by hash)
        try:
            block = rpc_connection.getblock(search_term)
            results["type"] = "block"
            results["id"] = search_term
            return results
        except JSONRPCException as e:
            pass

        # Try to get a transaction
        try:
            rawtx = rpc_connection.getrawtransaction(search_term)
            results["type"] = "tx"
            results["id"] = search_term
            return results
        except JSONRPCException as e:
            pass

    except Exception as e:
        results["type"] = "error"
        results["error_message"] = str(e)
    return results
    

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

@mynode_bitcoind.route("/explorer")
def bitcoind_explorer_page():
    # Get current information
    try:
        info = get_bitcoin_blockchain_info()
        blockdata = get_bitcoin_recent_blocks()
        mempool = get_bitcoin_mempool()

        # 10 most recent blocks
        blocks = []
        for b in blockdata:
            block = b
            minutes = int(time.time() - int(b["time"])) / 60
            block["age"] = "{} minutes".format(minutes)
            block["size"] = int(b["size"] / 1000)
            blocks.append(block)
        blocks.reverse()

    except Exception as e:
        templateData = {
            "title": "myNode Bitcoin Error",
            "message": Markup("Error communicating with bitcoind. Node may be busy syncing.<br/><br/>{}".format(str(e))),
            "back_url": "/"
        }
        return render_template('bitcoind_error.html', **templateData)


    templateData = {
        "title": "myNode Bitcoin Status",
        "blocks": blocks,
        "difficulty": "{:.3g}".format(info["difficulty"]),
        "block_num": info["blocks"],
        "header_num": info["headers"],
        "disk_size": (int(info["size_on_disk"]) / 1000 / 1000 / 1000),
        "mempool_tx": mempool["size"],
        "mempool_size": "{:.3} MB".format(float(mempool["bytes"]) / 1000 / 1000)
    }
    return render_template('bitcoind_explorer.html', **templateData)


@mynode_bitcoind.route("/explorer/search", methods=['POST'])
def search_page():
    if not request:
        return redirect("/explorer")

    results = search(request.form['search'])
    if results["type"] == "block":
        return redirect("/explorer/block/{}".format(results["id"]))
    elif results["type"] == "tx":
        return redirect("/explorer/tx/{}".format(results["id"]))
    elif results["type"] == "addr":
        return redirect("/explorer/addr/{}".format(results["id"]))
    elif results["type"] == "not_found":
        templateData = {
            "title": "myNode BTC Bitcoin Error",
            "message": Markup("Not Found<br/>{}".format(request.form['search']))
        }
        return render_template('bitcoind_error.html', **templateData)
    elif results["type"] == "error":
        templateData = {
            "title": "myNode Bitcoin Error",
            "message": Markup("Error<br/>{}".format(results["error_message"]))
        }
        return render_template('bitcoind_error.html', **templateData)

    templateData = {
        "title": "myNode Bitcoin Error",
        "message": Markup("Error - unknown return: {}".format(results["type"])),
    }
    return render_template('bitcoind_error.html', **templateData)

@mynode_bitcoind.route("/explorer/tx/<txid>")
def tx_page(txid):
    try:
        # Get info
        electrum_data = get_from_electrum("blockchain.transaction.get", [txid, True])
        tx = electrum_data['result']

        inputs = []
        outputs = []
        total = 0
        for i in tx["vin"]:
            if "coinbase" in i:
                inputs.append("New Coins")
            else:
                data = get_from_electrum("blockchain.transaction.get", [i["txid"], True])
                tx_data = data['result']
                inputs.append(tx_data["vout"][ i["vout"] ]["scriptPubKey"]["addresses"][0])
        for o in tx["vout"]:
            temp = {}
            if "scriptPubKey" in o:
                s = o["scriptPubKey"]
                if "type" in s and s["type"] != "nulldata":
                    if "addresses" in s:
                        temp["address"] = s["addresses"][0]
                    else:
                        temp["address"] = "Unable to decode address"
                    temp["amount"] = o["value"]
                    total += o["value"]
                    outputs.append(temp)

        confirmed = False
        confirmations = "Unconfirmed"
        block_height = 0
        block_date = ""
        if "confirmations" in tx:
            confirmations = tx["confirmations"]
            confirmed = True
        if confirmed:
            #block_height = tx["???"]
            t = time.gmtime( int(tx["blocktime"]) )
            block_date = time.strftime("%Y-%m-%d %H:%M:%S", t)

        templateData = {
            "title": "myNode Bitcoin",
            "heading": "Transaction",
            "raw": pformat(tx, indent=4),
            "txid": txid,
            "confirmations": confirmations,
            "size": tx["size"],
            "weight": tx["weight"],
            "confirmed": confirmed,
            "block_hash": tx["blockhash"],
            "block_height": tx,
            "block_date": block_date,
            "total": total,
            "inputs": inputs,
            "outputs": outputs
        }
        return render_template('bitcoind_tx.html', **templateData)
    except Exception as e:
        templateData = {
            "title": "myNode Bitcoin Error",
            "message": Markup("Error retreiving or parsing transaction.<br/><br/>{}".format(str(e)))
        }
        return render_template('bitcoind_error.html', **templateData)


@mynode_bitcoind.route("/explorer/block/<block_hash>")
def block_page(block_hash):
    try:
        # Get info
        rpc_user = get_bitcoin_rpc_username()
        rpc_pass = get_bitcoin_rpc_password()
        rpc_connection = AuthServiceProxy("http://%s:%s@127.0.0.1:8332"%(rpc_user, rpc_pass), timeout=10)
        block = rpc_connection.getblock(block_hash)
        
        txs = []
        for t in block["tx"]:
            txs.append(t)

        t = time.gmtime( int(block["time"]) )
        tstring = time.strftime("%Y-%m-%d %H:%M:%S", t)

        templateData = {
            "title": "myNode Bitcoin",
            "raw": pformat(block, indent=2),
            "height": block["height"],
            "hash": block["hash"],
            "confirmations": block["confirmations"],
            "num_tx": block["nTx"],
            "difficulty": "{:.3g}".format(block["difficulty"]),
            "size": int(block["size"] / 1000), 
            "date": tstring,
            "txs": txs
        }
        return render_template('bitcoind_block.html', **templateData)
    except Exception as e:
        templateData = {
            "title": "myNode Bitcoin Error",
            "message": Markup("Error communicating with bitcoind. Node may be busy syncing.<br/><br/>{}".format(str(e))),
            "back_url": "/bitcoind"
        }
        return render_template('bitcoind_error.html', **templateData)


@mynode_bitcoind.route("/explorer/addr/<addr>")
def address_page(addr):
    try:
        # Get addr info
        script_hash = get_scripthash_for_address(addr)

        rev = reverse_hash(script_hash)
        data = get_from_electrum('blockchain.scripthash.get_balance', rev)

        confirmed_bal = data["result"]["confirmed"]
        if confirmed_bal != 0:
            confirmed_bal = float(confirmed_bal) / 100000000
        unconfirmed_bal = data["result"]["unconfirmed"]
        if unconfirmed_bal != 0:
            unconfirmed_bal = float(unconfirmed_bal) / 100000000

        # Get addr TXs
        txdata = get_from_electrum('blockchain.scripthash.get_history', rev)
        unconfirmed = []
        confirmed = []
        for t in txdata['result']:
            if t["height"] == 0:
                unconfirmed.append(t)
            else:
                confirmed.append(t)
        confirmed = list(reversed(confirmed))
        txs = unconfirmed + confirmed

        templateData = {
            "title": "myNode Bitcoin",
            "address": addr,
            "confirmed_balance": confirmed_bal,
            "unconfirmed_balance": unconfirmed_bal,
            "txs": txs
        }
        return render_template('bitcoind_address.html', **templateData)
    except Exception as e:
        templateData = {
            "title": "myNode Bitcoin Error",
            "message": Markup("Error communicating with bitcoind. Node may be busy syncing.<br/><br/>{}".format(str(e))),
            "back_url": "/bitcoind"
        }
        return render_template('bitcoind_error.html', **templateData)