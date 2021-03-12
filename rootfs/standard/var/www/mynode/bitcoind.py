from flask import Blueprint, render_template, session, send_from_directory, abort, Markup, request, redirect, flash
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
from bitcoin_info import *
from device_info import *
#from bitcoin.wallet import *
from subprocess import check_output, check_call
from electrum_info import *
from user_management import check_logged_in
import socket
import hashlib
import json
import time

mynode_bitcoind = Blueprint('mynode_bitcoind',__name__)


def runcmd(cmd):
    cmd = "bitcoin-cli --conf=/home/admin/.bitcoin/bitcoin.conf --datadir=/mnt/hdd/mynode/bitcoin "+cmd+"; exit 0"
    try:
        results = subprocess.check_output(cmd, stderr=subprocess.STDOUT, shell=True)
    except Exception as e:
        results = str(e)
    return results


### Page functions
@mynode_bitcoind.route("/bitcoind")
def bitcoind_status_page():
    check_logged_in()

    # Get current information
    try:
        info = get_bitcoin_blockchain_info()
        blockdata = get_bitcoin_recent_blocks()
        peerdata  = get_bitcoin_peers()
        networkdata = get_bitcoin_network_info()
        walletdata = get_bitcoin_wallet_info()
        version = get_bitcoin_version()
        rpc_password = get_bitcoin_rpc_password()

        # Whitepaper
        bitcoin_whitepaper_exists = False
        if os.path.isfile("/mnt/hdd/mynode/bitcoin/bitcoin_whitepaper.pdf"):
            bitcoin_whitepaper_exists = True

        # Mempool info
        mempool = get_bitcoin_mempool_info()

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
            #blocks = blocks[:5] # Take top 5

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

        # Local address
        local_address = "..."
        if networkdata != None:
            local_address = "not none"
            if ("localaddresses" in networkdata) and (len(networkdata["localaddresses"]) > 0):
                local_address = "{}:{}".format(networkdata["localaddresses"][0]["address"], networkdata["localaddresses"][0]["port"])

        # Balance
        walletinfo = {}
        walletinfo["balance"] = 0.0
        walletinfo["unconfirmed_balance"] = 0.0
        if walletdata != None:
            if "balance" in walletdata:
                walletinfo["balance"] = walletdata["balance"]
            if "unconfirmed_balance" in walletdata:
                walletinfo["unconfirmed_balance"] = walletdata["unconfirmed_balance"]

    except Exception as e:
        templateData = {
            "title": "myNode Bitcoin Error",
            "message": Markup("Error communicating with bitcoind. Node may be busy syncing.<br/><br/>{}".format(str(e))),
            "ui_settings": read_ui_settings()
        }
        return render_template('bitcoind_status_error.html', **templateData)


    templateData = {
        "title": "myNode Bitcoin Status",
        "blocks": blocks,
        "peers": peers,
        "local_address": local_address,
        "difficulty": get_bitcoin_difficulty(),
        "block_num": info["blocks"],
        "header_num": info["headers"],
        "rpc_password": rpc_password,
        "disk_size": (int(info["size_on_disk"]) / 1000 / 1000 / 1000),
        "mempool_tx": mempool["size"],
        "mempool_size": "{:.3} MB".format(float(mempool["bytes"]) / 1000 / 1000),
        "is_testnet_enabled": is_testnet_enabled(),
        "confirmed_balance": walletinfo["balance"],
        "unconfirmed_balance": walletinfo["unconfirmed_balance"],
        "bitcoin_whitepaper_exists": bitcoin_whitepaper_exists,
        "version": version,
        "ui_settings": read_ui_settings()
    }
    return render_template('bitcoind_status.html', **templateData)

@mynode_bitcoind.route("/bitcoind/wallet.dat")
def bitcoin_wallet_dat():
    check_logged_in()
    return send_from_directory(directory="/mnt/hdd/mynode/bitcoin/", filename="wallet.dat")

@mynode_bitcoind.route("/bitcoind/bitcoin_whitepaper.pdf")
def bitcoin_whitepaper_pdf():
    check_logged_in()
    return send_from_directory(directory="/mnt/hdd/mynode/bitcoin/", filename="bitcoin_whitepaper.pdf")

@mynode_bitcoind.route("/bitcoind/reset_config")
def bitcoin_reset_config_page():
    check_logged_in()

    delete_bitcoin_custom_config()
        
    # Trigger reboot
    t = Timer(1.0, reboot_device)
    t.start()

    # Wait until device is restarted
    templateData = {
        "title": "myNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_bitcoind.route("/bitcoind/config", methods=['GET','POST'])
def bitcoind_config_page():
    check_logged_in()

    # Handle form
    if request.method == 'POST':
        custom_config = request.form.get('custom_config')
        set_bitcoin_custom_config(custom_config)
        
        # Trigger reboot
        t = Timer(1.0, reboot_device)
        t.start()

        # Wait until device is restarted
        templateData = {
            "title": "myNode Reboot",
            "header_text": "Restarting",
            "subheader_text": "This will take several minutes...",
            "ui_settings": read_ui_settings()
        }
        return render_template('reboot.html', **templateData)

    bitcoin_config = get_bitcoin_custom_config()
    if bitcoin_config == "ERROR":
        bitcoin_config = get_bitcoin_config()

    templateData = {
        "title": "myNode Bitcoin Config",
        "using_bitcoin_custom_config": using_bitcoin_custom_config(),
        "bitcoin_config": bitcoin_config,
        "ui_settings": read_ui_settings()
    }
    return render_template('bitcoind_config.html', **templateData)

@mynode_bitcoind.route("/bitcoind/cli")
def bitcoincli():
    check_logged_in()

    # Load page
    templateData = {
        "title": "myNode Bitcoin CLI",
        "ui_settings": read_ui_settings()
    }
    return render_template('bitcoin_cli.html', **templateData)

@mynode_bitcoind.route("/bitcoind/cli-run", methods=['POST'])
def runcmd_page():
    check_logged_in()
    
    if not request:
        return ""
    response = runcmd(request.form['cmd'])
    return response
