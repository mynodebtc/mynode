from flask import Blueprint, render_template, session, abort, Markup, request, redirect, flash
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
from bitcoin_info import *
from device_info import *
#from bitcoin.wallet import *
from subprocess import check_output, check_call
from electrum_info import *
from user_management import check_logged_in
import socket
import json
import time

mynode_bitcoin = Blueprint('mynode_bitcoin',__name__)


def cleanup_download_wallets():
    os.system("rm -rf /tmp/download_wallets/*")

### Page functions
@mynode_bitcoin.route("/bitcoin")
def bitcoin_status_page():
    check_logged_in()

    # Get current information
    try:
        info = get_bitcoin_blockchain_info()
        blockdata = get_bitcoin_recent_blocks()
        peerdata  = get_bitcoin_peers()
        networkdata = get_bitcoin_network_info()
        walletdata = get_bitcoin_wallets()
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
                block["age"] = "{} minutes".format( int(minutes) )
                block["size"] = int(b["size"] / 1000)
                blocks.append(block)
            blocks.reverse()
            #blocks = blocks[:5] # Take top 5

        # Peers
        peers = peerdata

        # Bitcoin address
        addresses = ["..."]
        if networkdata != None:
            addresses = ["no local addresses"]
            if ("localaddresses" in networkdata) and (len(networkdata["localaddresses"]) > 0):
                addresses = []
                for addr in networkdata["localaddresses"]:
                    addresses.append("{}:{}".format(addr["address"], addr["port"]))


    except Exception as e:
        templateData = {
            "title": "MyNode Bitcoin Error",
            "header": "Bitcoin Status",
            "message": Markup("Error communicating with bitcoin. Node may be busy syncing.<br/><br/>{}".format(str(e))),
            "ui_settings": read_ui_settings()
        }
        return render_template('error.html', **templateData)


    templateData = {
        "title": "MyNode Bitcoin Status",
        "blocks": blocks,
        "peers": peers,
        "addresses": addresses,
        "difficulty": get_bitcoin_difficulty(),
        "block_num": info["blocks"],
        "header_num": info["headers"],
        "rpc_password": rpc_password,
        "disk_usage": get_bitcoin_disk_usage(),
        "mempool_tx": mempool["count"],
        "mempool_size": mempool["display_bytes"],
        "is_testnet_enabled": is_testnet_enabled(),
        "wallets": walletdata,
        "bitcoin_whitepaper_exists": bitcoin_whitepaper_exists,
        "version": version,
        "bip37_enabled": is_bip37_enabled(),
        "bip157_enabled": is_bip157_enabled(),
        "bip158_enabled": is_bip158_enabled(),
        "ui_settings": read_ui_settings()
    }
    return render_template('bitcoin.html', **templateData)

@mynode_bitcoin.route("/bitcoin/download_wallet", methods=["GET"])
def bitcoin_download_wallet():
    check_logged_in()
    wallet_name = request.args.get('wallet')
    if wallet_name is None:
        flash("Error finding wallet to download!", category="error")
        return redirect("/bitcoin")

    os.system("mkdir -p /tmp/download_wallets")
    os.system("chmod 777 /tmp/download_wallets")
    run_bitcoincli_command("-rpcwallet='"+wallet_name+"' dumpwallet '/tmp/download_wallets/"+wallet_name+"'")

    if not os.path.isfile("/tmp/download_wallets/"+wallet_name):
        flash("Error exporting wallet data for download", category="error")
        return redirect("/bitcoin")

    t = Timer(3.0, cleanup_download_wallets)
    t.start()

    return download_file(directory="/tmp/download_wallets/", filename=wallet_name)

@mynode_bitcoin.route("/bitcoin/delete_wallet", methods=["GET"])
def bitcoin_delete_wallet():
    check_logged_in()
    wallet_name = request.args.get('wallet')
    if wallet_name is None:
        flash("Error finding wallet to delete!", category="error")
        return redirect("/bitcoin")

    run_bitcoincli_command("unloadwallet {}".format(wallet_name))
    run_linux_cmd("rm -rf /mnt/hdd/mynode/bitcoin/{}".format(wallet_name))

    # Update wallet info
    update_bitcoin_other_info()

    flash("Wallet Deleted", category="message")
    return redirect("/bitcoin")

@mynode_bitcoin.route("/bitcoin/bitcoin_whitepaper.pdf")
def bitcoin_whitepaper_pdf():
    check_logged_in()
    return download_file(directory="/mnt/hdd/mynode/bitcoin/", filename="bitcoin_whitepaper.pdf")

@mynode_bitcoin.route("/bitcoin/reset_config")
def bitcoin_reset_config_page():
    check_logged_in()

    delete_bitcoin_custom_config()
        
    # Trigger reboot
    t = Timer(1.0, reboot_device)
    t.start()

    # Wait until device is restarted
    templateData = {
        "title": "MyNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_bitcoin.route("/bitcoin/config", methods=['GET','POST'])
def bitcoin_config_page():
    check_logged_in()

    # Handle form
    if request.method == 'POST':
        custom_config = request.form.get('custom_config')
        extra_bitcoin_config = request.form.get('extra_bitcoin_config')
        if extra_bitcoin_config != None:
            set_bitcoin_extra_config(extra_bitcoin_config)
        if custom_config != None:
            set_bitcoin_custom_config(custom_config)
        
        # Trigger reboot
        t = Timer(1.0, reboot_device)
        t.start()

        # Wait until device is restarted
        templateData = {
            "title": "MyNode Reboot",
            "header_text": "Restarting",
            "subheader_text": "This will take several minutes...",
            "ui_settings": read_ui_settings()
        }
        return render_template('reboot.html', **templateData)

    bitcoin_config = get_bitcoin_custom_config()
    if bitcoin_config == "ERROR":
        bitcoin_config = get_bitcoin_config()

    templateData = {
        "title": "MyNode Bitcoin Config",
        "using_bitcoin_custom_config": using_bitcoin_custom_config(),
        "extra_bitcoin_config": get_bitcoin_extra_config(),
        "bitcoin_config": bitcoin_config,
        "ui_settings": read_ui_settings()
    }
    return render_template('bitcoin_config.html', **templateData)

@mynode_bitcoin.route("/bitcoin/cli")
def bitcoincli():
    check_logged_in()

    # Load page
    templateData = {
        "title": "MyNode Bitcoin Terminal",
        "ui_settings": read_ui_settings()
    }
    return render_template('bitcoin_cli.html', **templateData)

@mynode_bitcoin.route("/bitcoin/cli-run", methods=['POST'])
def runcmd_page():
    check_logged_in()
    
    if not request:
        return ""
    response = run_bitcoincli_command(request.form['cmd'])
    return response

@mynode_bitcoin.route("/bitcoin/toggle_bip37")
def bitcoin_toggle_bip37():
    if request.args.get("enabled") and request.args.get("enabled") == "1":
        enable_bip37()
    else:
        disable_bip37()

    # Trigger reboot
    t = Timer(1.0, reboot_device)
    t.start()

    # Wait until device is restarted
    templateData = {
        "title": "MyNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_bitcoin.route("/bitcoin/toggle_bip157")
def bitcoin_toggle_bip157():
    if request.args.get("enabled") and request.args.get("enabled") == "1":
        enable_bip157()
    else:
        disable_bip157()

    # Trigger reboot
    t = Timer(1.0, reboot_device)
    t.start()

    # Wait until device is restarted
    templateData = {
        "title": "MyNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_bitcoin.route("/bitcoin/toggle_bip158")
def bitcoin_toggle_bip158():
    check_logged_in()

    if request.args.get("enabled") and request.args.get("enabled") == "1":
        enable_bip158()
    else:
        disable_bip158()

    # Trigger reboot
    t = Timer(1.0, reboot_device)
    t.start()

    # Wait until device is restarted
    templateData = {
        "title": "MyNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)
