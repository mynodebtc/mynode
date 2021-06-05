from flask import Blueprint, render_template, session, abort, Markup, request, redirect, send_from_directory, url_for, flash
from pprint import pprint, pformat
from threading import Timer
from bitcoin_info import *
from lightning_info import *
from settings import reboot_device, read_ui_settings
from device_info import *
from utilities import *
from user_management import check_logged_in
from werkzeug.utils import secure_filename
import urllib
import traceback
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

def get_image_src_b64(filename):
    return "data:image/png;base64," + get_image_contents(filename)

# Flask Pages
@mynode_lnd.route("/lnd")
def page_lnd():
    check_logged_in()

    height = 0
    refresh_rate = 3600
    alias = get_lnd_alias_file_data()
    num_peers = "0"
    num_active_channels = "TODO"
    num_pending_channels = "TODO"
    num_inactive_channels = "TODO"
    pubkey = "abcd"
    uri = ""
    ip = ""
    status = "Starting..."
    lnd_deposit_address = get_lnd_deposit_address()
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
            "watchtower_enabled": is_watchtower_enabled(),
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
            "watchtower_enabled": is_watchtower_enabled(),
            "alias": alias,
            "status": get_lnd_status(),
            "version": get_lnd_version(),
            "loop_version": get_loop_version(),
            "pool_version": get_pool_version(),
            "refresh_rate": 10,
            "ui_settings": read_ui_settings()
        }
        return render_template('lnd.html', **templateData)

    try:
        data = get_lightning_info()

        # If lightning data is still None, show message
        if data == None:
            templateData = {
                "title": "myNode Lightning Wallet",
                "wallet_exists": wallet_exists,
                "wallet_logged_in": False,
                "watchtower_enabled": is_watchtower_enabled(),
                "alias": alias,
                "status": "Waiting on LND data...",
                "version": get_lnd_version(),
                "loop_version": get_loop_version(),
                "pool_version": get_pool_version(),
                "refresh_rate": 10,
                "ui_settings": read_ui_settings()
            }
            return render_template('lnd.html', **templateData)

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

        peers = get_lightning_peers()
        channels = get_lightning_channels()
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

        # Update TX info
        update_lightning_tx_info()
        transactions = get_lightning_transactions()
        payments = get_lightning_payments()
        invoices = get_lightning_invoices()

        watchtower_server_info = get_lightning_watchtower_server_info()
        watchtower_uri = "..."
        if watchtower_server_info != None:
            if "uris" in watchtower_server_info and len(watchtower_server_info['uris']) > 0:
                watchtower_uri = watchtower_server_info['uris'][0]

            
    except Exception as e:
        templateData = {
            "title": "myNode Lightning Status",
            "header": "Lightning Status",
            #"message": str(e),
            "message": traceback.format_exc(),
            "refresh_rate": 10,
            "ui_settings": read_ui_settings()
        }
        return render_template('error.html', **templateData)

    if not is_lnd_ready():
        refresh_rate = 15

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
        "watchtower_enabled": is_watchtower_enabled(),
        "lit_password": get_lnd_lit_password(),
        "lnd_deposit_address": lnd_deposit_address,
        "channel_balance": format_sat_amount(balance_info["channel_balance"]),
        "channel_pending": format_sat_amount(balance_info["channel_pending"]),
        "wallet_balance": format_sat_amount(balance_info["wallet_balance"]),
        "wallet_pending": format_sat_amount(balance_info["wallet_pending"]),
        "watchtower_uri": watchtower_uri,
        "peers": peers,
        "channels": channels,
        "transactions": transactions,
        "payments": payments,
        "invoices": invoices,
        "tx_display_limit": 8,
        "refresh_rate": refresh_rate,
        "ui_settings": read_ui_settings()
    }
    return render_template('lnd.html', **templateData)

@mynode_lnd.route("/lnd/regen_tls_cert")
def lnd_regen_tls_cert():
    check_logged_in()

    os.system("rm /mnt/hdd/mynode/lnd/tls.cert")
    os.system("rm /mnt/hdd/mynode/lnd/tls.key")

    t = Timer(3.0, restart_lnd)
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
            "show_lightning_back_button": True,
            "header": "Lightning Status",
            "message": Markup("Waiting on Lightning...<br/>Please try again in a minute."),
            "ui_settings": read_ui_settings()
        }
        return render_template('error.html', **templateData)

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


def create_pair(name, image_src, text, premium):
    pair = {}
    pair["name"] = name
    pair["id"] = name.replace(" ","").replace("+","").replace("(","").replace(")","").lower()
    pair["image_src"] = image_src.strip()
    pair["text"] = text.strip()
    pair["premium"] = premium
    if is_community_edition() and premium:
        pair["image_src"] = get_image_src_b64("/var/www/mynode/static/images/dots.png")
        pair["text"] = "Premium Feature"
    return pair

@mynode_lnd.route("/lnd/pair_wallet", methods=["GET","POST"])
def page_lnd_pair_wallet():
    check_logged_in()

    # Load page
    if request.method == 'GET':
        return redirect(url_for(".page_lnd"))

    p = pam.pam()
    pw = request.form.get('password_pair_wallet')
    from_homepage = request.form.get('pair_wallet_from_homepage')
    if pw == None or p.authenticate("admin", pw) == False:
        if from_homepage != None:
            flash("Invalid Password", category="error")
            return redirect("/")
        else:
            flash("Invalid Password", category="error")
            return redirect(url_for(".page_lnd"))

    # Lndconnect Data
    lndconnect_local_grpc_text = get_text_contents("/tmp/mynode_lndconnect/lndconnect_local_grpc.txt")
    lndconnect_local_rest_text = get_text_contents("/tmp/mynode_lndconnect/lndconnect_local_rest.txt")
    lndconnect_tor_grpc_text = get_text_contents("/tmp/mynode_lndconnect/lndconnect_tor_grpc.txt")
    lndconnect_tor_rest_text = get_text_contents("/tmp/mynode_lndconnect/lndconnect_tor_rest.txt")

    lndconnect_local_grpc_img = get_image_src_b64("/tmp/mynode_lndconnect/lndconnect_local_grpc.png")
    lndconnect_local_rest_img = get_image_src_b64("/tmp/mynode_lndconnect/lndconnect_local_rest.png")
    lndconnect_tor_grpc_img = get_image_src_b64("/tmp/mynode_lndconnect/lndconnect_tor_grpc.png")
    lndconnect_tor_rest_img = get_image_src_b64("/tmp/mynode_lndconnect/lndconnect_tor_rest.png")

    # Blue Wallet Data
    electrs_onion_url = get_onion_url_electrs()
    lndhub_onion_url = get_onion_url_lndhub()
    local_ip = get_local_ip()
    #LNDhub QR:
    #bluewallet:setlndhuburl?url=http%3A%2F%2Fg45wix2qhsxtoz2k675ikmlt5ypmcoz4nyhy44teku7amb7vqoh7jyyd.onion:3001

    #Electrum QR:
    #bluewallet:setelectrumserver?server=v7gtzf7nua6hdmb2wtqaqioqmesdb4xrlly4zwr7bvayxv2bpg665pqd.onion%3A50001%3At
    bluewallet_lndhub_local_text = "bluewallet:setlndhuburl?url=http://"+local_ip+":3000"
    bluewallet_lndhub_local_img = "/api/get_qr_code_image?url="+urllib.quote_plus(bluewallet_lndhub_local_text)
    bluewallet_lndhub_tor_text = "bluewallet:setlndhuburl?url=http://"+lndhub_onion_url+":3000"
    bluewallet_lndhub_tor_img = "/api/get_qr_code_image?url="+urllib.quote_plus(bluewallet_lndhub_tor_text)
    bluewallet_electrs_local_text = "bluewallet:setelectrumserver?server="+local_ip+":50002"
    bluewallet_electrs_local_img = "/api/get_qr_code_image?url="+urllib.quote_plus(bluewallet_electrs_local_text)
    bluewallet_electrs_tor_text = "bluewallet:setelectrumserver?server="+electrs_onion_url+":50002"
    bluewallet_electrs_tor_img = "/api/get_qr_code_image?url="+urllib.quote_plus(bluewallet_electrs_tor_text)


    # Pairing options
    pairs = []
    pairs.append( create_pair(name="Lightning (gRPC + Local IP)", image_src=lndconnect_local_grpc_img,text=lndconnect_local_grpc_text,premium=False) )
    pairs.append( create_pair(name="Lightning (gRPC + Tor)", image_src=lndconnect_tor_grpc_img,text=lndconnect_tor_grpc_text,premium=True) )
    pairs.append( create_pair(name="Lightning (REST + Local IP)", image_src=lndconnect_local_rest_img,text=lndconnect_local_rest_text,premium=False) )
    pairs.append( create_pair(name="Lightning (REST + Tor)", image_src=lndconnect_tor_rest_img,text=lndconnect_tor_rest_text,premium=True) )
    pairs.append( create_pair(name="Blue Wallet (LNDHub + Local IP)", image_src=bluewallet_lndhub_local_img,text=bluewallet_lndhub_local_text,premium=False) )
    pairs.append( create_pair(name="Blue Wallet (LNDHub + Tor)", image_src=bluewallet_lndhub_tor_img,text=bluewallet_lndhub_tor_text,premium=True) )
    pairs.append( create_pair(name="Blue Wallet (Electrum + Local IP)", image_src=bluewallet_electrs_local_img,text=bluewallet_electrs_local_text,premium=False) )
    pairs.append( create_pair(name="Blue Wallet (Electrum + Tor)", image_src=bluewallet_electrs_tor_img,text=bluewallet_electrs_tor_text,premium=True) )
    #pairs.append( create_pair(name="Fully Noded (Tor)", image_src="",text="",premium=True) ) # Maybe not? pairs diff wallet
    

    # Show lndconnect page
    templateData = {
        "title": "myNode Lightning Wallet",
        "dots_img": get_image_src_b64("/var/www/mynode/static/images/dots.png"),
        "pairs": pairs,
        "ui_settings": read_ui_settings()
    }
    return render_template('pair_wallet.html', **templateData)


@mynode_lnd.route("/lnd/change_alias", methods=["POST"])
def page_lnd_change_alias():
    check_logged_in()

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

    # Restart LND
    restart_lnd()

    flash("Alias updated!", category="message")
    return redirect(url_for(".page_lnd"))

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

@mynode_lnd.route("/lnd/set_watchtower_enabled")
def lnd_set_watchtower_enabled_page():
    check_logged_in()

    if request.args.get("enabled") and request.args.get("enabled") == "1":
        enable_watchtower()
    else:
        disable_watchtower()

    restart_lnd()

    flash("Watchtower settings updated!", category="message")
    return redirect(url_for(".page_lnd"))

##############################################
## LND API Calls
##############################################
@mynode_lnd.route("/lnd/api/get_new_lnd_deposit_address", methods=['GET'])
def lnd_api_get_new_lnd_deposit_address_page():
    check_logged_in()

    address = get_new_lnd_deposit_address()
    return address