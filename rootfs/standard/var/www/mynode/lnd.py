from flask import Blueprint, render_template, session, abort, Markup, request, redirect, send_from_directory, url_for, flash
from pprint import pprint, pformat
from threading import Timer
from bitcoin_info import *
from lightning_info import *
from settings import reboot_device, read_ui_settings
from device_info import *
from user_management import check_logged_in
from werkzeug.utils import secure_filename
import base64
import subprocess
import json
import pam
import time
import re
import requests
import os


mynode_lnd = Blueprint('mynode_lnd',__name__)

# Helper functions
def get_text_contents(filename):
    try:
        with open(filename) as f:
            return f.read()
    except:
        return "EXCEPTION"
    return "ERROR"

def get_image_contents(filename):
    try:
        with open(filename, "rb") as image_file:
            encoded_string = base64.b64encode(image_file.read())
            return encoded_string
    except:
        return "EXCEPTION"
    return "ERROR"

# Flask Pages
@mynode_lnd.route("/lnd")
def page_lnd():
    check_logged_in()

    height = 0
    alias = get_lnd_alias_file_data()
    num_peers = "0"
    num_active_channels = "TODO"
    num_pending_channels = "TODO"
    num_inactive_channels = "TODO"
    pubkey = "abcd"
    uri = ""
    ip = ""
    status = "Starting..."
    lnd_deposit_address = get_deposit_address()
    channel_balance = "N/A"
    channel_pending = "0"
    wallet_balance = "N/A"
    wallet_pending = "0"

    wallet_exists = lnd_wallet_exists()
    wallet_logged_in = is_lnd_logged_in()
    channel_backup_exists = lnd_channel_backup_exists()

    if not lnd_wallet_exists():
        templateData = {
            "title": "myNode Lightning Wallet",
            "wallet_exists": wallet_exists,
            "wallet_logged_in": wallet_logged_in,
            "version": get_lnd_version(),
            "loop_version": get_loop_version(),
            "pool_version": get_pool_version(),
            "status": "Please Create Wallet",
            "ui_settings": read_ui_settings()
        }
        return render_template('lnd.html', **templateData)

    if not is_lnd_logged_in():
        templateData = {
            "title": "myNode Lightning Wallet",
            "wallet_exists": wallet_exists,
            "wallet_logged_in": wallet_logged_in,
            "alias": alias,
            "status": get_lnd_status(),
            "version": get_lnd_version(),
            "loop_version": get_loop_version(),
            "pool_version": get_pool_version(),
            "ui_settings": read_ui_settings()
        }
        return render_template('lnd.html', **templateData)

    try:
        data = get_lightning_info()

        if "block_height" in data:
            height = data['block_height']
        if "identity_pubkey" in data:
            pubkey = data['identity_pubkey']
        if "num_peers" in data:
            num_peers = data['num_peers']
        if "synced_to_chain" in data and data['synced_to_chain']:
            status = "Active"
        else:
            status = get_lnd_status()
        if "uris" in data and len(data['uris']) > 0:
            uri = data['uris'][0]
            ip = uri.split("@")[1]
        else:
            uri = "..."
            ip = "..."

        peerdata = get_lightning_peers()
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
                    peer["sat_sent"] = format_sat_amount(peer["sat_sent"])
                if "sat_recv" in p:
                    peer["sat_recv"] = format_sat_amount(peer["sat_recv"])
                if "ping_time" not in p:
                    peer["ping_time"] = "N/A"
                if "pub_key" in p:
                    peer["alias"] = get_lightning_peer_alias( p["pub_key"] )
                else:
                    peer["alias"] = "Unknown"
                peers.append(peer)

        channeldata = get_lightning_channels()
        channels = []
        if channeldata != None and "channels" in channeldata:
            for c in channeldata["channels"]:
                channel = c
                if "capacity" in channel:
                    channel["capacity"] = format_sat_amount(channel["capacity"])
                if "local_balance" not in channel:
                    channel["local_balance"] = "0"
                else:
                    channel["local_balance"] = format_sat_amount(channel["local_balance"])
                if "remote_balance" not in channel:
                    channel["remote_balance"] = "0"
                else:
                    channel["remote_balance"] = format_sat_amount(channel["remote_balance"])
                if "remote_pubkey" in channel:
                    channel["remote_alias"] = get_lightning_peer_alias( channel["remote_pubkey"] )
                else:
                    channel["remote_alias"] = "Unknown"
                channels.append(channel)

        balance_info = get_lightning_balance_info()

        channel_balance_data = get_lightning_channel_balance()
        if channel_balance_data != None and "balance" in channel_balance_data:
            channel_balance = channel_balance_data["balance"]
        if channel_balance_data != None and "pending_open_balance" in channel_balance_data:
            channel_pending = channel_balance_data["pending_open_balance"]
        
        wallet_balance_data = get_lightning_wallet_balance()
        if wallet_balance_data != None and "confirmed_balance" in wallet_balance_data:
            wallet_balance = wallet_balance_data["confirmed_balance"]
        if wallet_balance_data != None and "unconfirmed_balance" in wallet_balance_data:
            wallet_pending = wallet_balance_data["unconfirmed_balance"]

            
    except Exception as e:
        templateData = {
            "title": "myNode Lightning Status",
            "message": str(e),
            "ui_settings": read_ui_settings()
        }
        return render_template('lnd_error.html', **templateData)

    templateData = {
        "title": "myNode Lightning Status",
        "wallet_exists": wallet_exists,
        "wallet_logged_in": wallet_logged_in,
        "version": get_lnd_version(),
        "loop_version": get_loop_version(),
        "pool_version": get_pool_version(),
        "is_testnet_enabled": is_testnet_enabled(),
        "channel_backup_exists": channel_backup_exists,
        "status": status,
        "height": height,
        "alias": alias,
        "num_peers": num_peers,
        "num_active_channels": num_active_channels,
        "num_pending_channels": num_pending_channels,
        "num_inactive_channels": num_inactive_channels,
        "pubkey": pubkey,
        "uri": uri,
        "ip": ip,
        "lnd_deposit_address": lnd_deposit_address,
        "channel_balance": format_sat_amount(balance_info["channel_balance"]),
        "channel_pending": format_sat_amount(balance_info["channel_pending"]),
        "wallet_balance": format_sat_amount(balance_info["wallet_balance"]),
        "wallet_pending": format_sat_amount(balance_info["wallet_pending"]),
        "peers": peers,
        "channels": channels,
        "ui_settings": read_ui_settings()
    }
    return render_template('lnd.html', **templateData)

@mynode_lnd.route("/lnd/regen_tls_cert")
def lnd_regen_tls_cert():
    check_logged_in()

    os.system("rm /mnt/hdd/mynode/lnd/tls.cert")
    os.system("rm /mnt/hdd/mynode/lnd/tls.key")

    t = Timer(1.0, restart_lnd)
    t.start()

    flash("TLS Certificate Regenerated!", category="message")
    return redirect(url_for(".page_lnd"))

@mynode_lnd.route("/lnd/tls.cert")
def lnd_tls_cert():
    check_logged_in()
    return send_from_directory(directory="/mnt/hdd/mynode/lnd/", filename="tls.cert")

@mynode_lnd.route("/lnd/admin.macaroon")
def lnd_admin_macaroon():
    check_logged_in()

    folder = "mainnet"
    if is_testnet_enabled():
        folder = "testnet"

    # Download macaroon
    return send_from_directory(directory="/mnt/hdd/mynode/lnd/data/chain/bitcoin/{}/".format(folder), filename="admin.macaroon")

@mynode_lnd.route("/lnd/readonly.macaroon")
def lnd_readonly_macaroon():
    check_logged_in()

    folder = "mainnet"
    if is_testnet_enabled():
        folder = "testnet"

    # Download macaroon
    return send_from_directory(directory="/mnt/hdd/mynode/lnd/data/chain/bitcoin/{}/".format(folder), filename="readonly.macaroon")

@mynode_lnd.route("/lnd/channel.backup")
def lnd_channel_backup():
    check_logged_in()

    scb_location = get_lnd_channel_backup_file()
    parts = os.path.split(scb_location)

    return send_from_directory(directory=parts[0]+"/", filename=parts[1])

@mynode_lnd.route("/lnd/create_wallet")
def page_lnd_create_wallet():
    check_logged_in()

    try:
        seed = gen_new_wallet_seed()
        session['seed'] = seed.strip()
    except:
        templateData = {
            "title": "myNode Lightning Wallet",
            "message": Markup("Waiting on Lightning...<br/>Please try again in a minute."),
            "ui_settings": read_ui_settings()
        }
        return render_template('lnd_error.html', **templateData)

    templateData = {
        "title": "myNode Lightning Wallet",
        "seed": seed,
        "ui_settings": read_ui_settings()
    }
    return render_template('lnd_wallet_create.html', **templateData)

@mynode_lnd.route("/lnd/create_wallet_with_seed", methods=['GET','POST'])
def page_lnd_create_wallet_with_seed():
    check_logged_in()

    # Load page
    if request.method == 'GET':
        templateData = {
            "title": "myNode Lightning Wallet",
            "ui_settings": read_ui_settings()
        }
        return render_template('lnd_wallet_create_with_seed.html', **templateData)

    # Get seed
    seed = request.form.get('seed').strip()

    # Check for channel backup
    channel_backup_filename = "/tmp/lnd_channel_backup"
    os.system("rm -f " + channel_backup_filename)

    if 'channel_backup' in request.files and request.files['channel_backup'] != "":
        f = request.files['channel_backup']
        if f.filename != "":
            f.save( channel_backup_filename )

    if create_wallet(seed):
        flash("Wallet Created!", category="message")
        return redirect(url_for(".page_lnd"))
    
    # Error creating wallet
    flash("Error Creating Wallet!", category="error")
    return redirect(url_for(".page_lnd"))


@mynode_lnd.route("/lnd/create_wallet_confirm", methods=['GET','POST'])
def page_lnd_create_wallet_confirm():
    check_logged_in()

    # Load page
    if request.method == 'GET':
        templateData = {
            "title": "myNode Lightning Wallet",
            "ui_settings": read_ui_settings()
        }
        return render_template('lnd_wallet_create_confirm.html', **templateData)

    # Parse submission
    seed = request.form.get('seed').strip()
    if seed != session['seed']:
        session["seed"] = None
        flash("Incorrect Seed", category="error")
        return redirect(url_for(".page_lnd"))
    session["seed"] = None

    # Seed matches, create wallet!
    if create_wallet(seed):
        flash("Wallet Created!", category="message")
        return redirect(url_for(".page_lnd"))
    
    # Error creating wallet
    flash("Error Creating Wallet!", category="error")
    return redirect(url_for(".page_lnd"))


@mynode_lnd.route("/lnd/lndconnect", methods=["GET","POST"])
def page_lnd_lndconnect():
    check_logged_in()

    # Load page
    if request.method == 'GET':
        return redirect(url_for(".page_lnd"))

    p = pam.pam()
    pw = request.form.get('password_lndconnect')
    from_homepage = request.form.get('lndconnect_from_homepage')
    if pw == None or p.authenticate("admin", pw) == False:
        if from_homepage != None:
            flash("Invalid Password", category="error")
            return redirect("/")
        else:
            flash("Invalid Password", category="error")
            return redirect(url_for(".page_lnd"))

    lndconnect_local_grpc_text = get_text_contents("/tmp/mynode_lndconnect/lndconnect_local_grpc.txt")
    lndconnect_local_rest_text = get_text_contents("/tmp/mynode_lndconnect/lndconnect_local_rest.txt")
    lndconnect_tor_grpc_text = get_text_contents("/tmp/mynode_lndconnect/lndconnect_tor_grpc.txt")
    lndconnect_tor_rest_text = get_text_contents("/tmp/mynode_lndconnect/lndconnect_tor_rest.txt")
    if is_community_edition():
        lndconnect_tor_grpc_text = "Premium Feature"
        lndconnect_tor_rest_text = "Premium Feature"

    lndconnect_local_grpc_img = get_image_contents("/tmp/mynode_lndconnect/lndconnect_local_grpc.png")
    lndconnect_local_rest_img = get_image_contents("/tmp/mynode_lndconnect/lndconnect_local_rest.png")
    lndconnect_tor_grpc_img = get_image_contents("/tmp/mynode_lndconnect/lndconnect_tor_grpc.png")
    lndconnect_tor_rest_img = get_image_contents("/tmp/mynode_lndconnect/lndconnect_tor_rest.png")
    if is_community_edition():
        lndconnect_tor_grpc_img = get_image_contents("/var/www/mynode/static/images/dots.png")
        lndconnect_tor_rest_img = get_image_contents("/var/www/mynode/static/images/dots.png")

    # Show lndconnect page
    templateData = {
        "title": "myNode Lightning Wallet",
        "lndconnect_local_grpc_text": lndconnect_local_grpc_text,
        "lndconnect_local_rest_text": lndconnect_local_rest_text,
        "lndconnect_tor_grpc_text": lndconnect_tor_grpc_text,
        "lndconnect_tor_rest_text": lndconnect_tor_rest_text,
        "lndconnect_local_grpc_img": lndconnect_local_grpc_img,
        "lndconnect_local_rest_img": lndconnect_local_rest_img,
        "lndconnect_tor_grpc_img": lndconnect_tor_grpc_img,
        "lndconnect_tor_rest_img": lndconnect_tor_rest_img,
        "ui_settings": read_ui_settings()
    }
    return render_template('lndconnect.html', **templateData)


@mynode_lnd.route("/lnd/change_alias", methods=["POST"])
def page_lnd_change_alias():
    check_logged_in()
    
    # Load page
    p = pam.pam()
    pw = request.form.get('password_change_alias')
    if pw == None or p.authenticate("admin", pw) == False:
        flash("Invalid Password", category="error")
        return redirect(url_for(".page_lnd"))

    # Change alias
    alias = request.form.get('alias')
    if alias == None or alias == "":
        flash("Empty Alias", category="error")
        return redirect(url_for(".page_lnd"))
    if len(alias) > 34:
        flash("Invalid Alias", category="error")
        return redirect(url_for(".page_lnd"))
    with open("/mnt/hdd/mynode/settings/.lndalias", "w") as f:
        utf8_alias = alias.decode('utf-8', 'ignore')
        f.write(utf8_alias)
        f.close()

    # Reboot
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

@mynode_lnd.route("/lnd/reset_config")
def lnd_reset_config_page():
    check_logged_in()

    delete_lnd_custom_config()
        
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

@mynode_lnd.route("/lnd/config", methods=['GET','POST'])
def lnd_config_page():
    check_logged_in()

    # Handle form
    if request.method == 'POST':
        custom_config = request.form.get('custom_config')
        set_lnd_custom_config(custom_config)
        
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

    lnd_config = get_lnd_custom_config()
    if lnd_config == "ERROR":
        lnd_config = get_lnd_config()

    templateData = {
        "title": "myNode LND Config",
        "using_lnd_custom_config": using_lnd_custom_config(),
        "lnd_config": lnd_config,
        "ui_settings": read_ui_settings()
    }
    return render_template('lnd_config.html', **templateData)


##############################################
## LND API Calls
##############################################
@mynode_lnd.route("/lnd/api/get_new_deposit_address", methods=['GET'])
def lnd_api_get_new_deposit_address_page():
    check_logged_in()

    address = get_new_deposit_address()
    return address