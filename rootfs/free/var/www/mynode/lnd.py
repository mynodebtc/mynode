from flask import Blueprint, render_template, session, abort, Markup, request, redirect, send_from_directory, url_for
from pprint import pprint, pformat
from threading import Timer
from bitcoin_info import *
from lightning_info import *
import base64
import subprocess
import json
import pam
import time
import re
import requests
import os.path


mynode_lnd = Blueprint('mynode_lnd',__name__)

# Flask Pages
@mynode_lnd.route("/lnd")
def page_lnd():
    height = 0
    alias = "empty"
    num_peers = "0"
    num_active_channels = "TODO"
    num_pending_channels = "TODO"
    num_inactive_channels = "TODO"
    pubkey = "abcd"
    uri = ""
    ip = ""
    status = "Starting..."

    wallet_exists = lnd_wallet_exists()
    wallet_logged_in = is_lnd_logged_in()

    message = ""
    if request.args.get('error_message'):
        message = Markup("<div class='error_message'>"+request.args.get('error_message')+"</div>")
    if request.args.get('success_message'):
        message = Markup("<div class='success_message'>"+request.args.get('success_message')+"</div>")

    if not lnd_wallet_exists():
        templateData = {
            "title": "myNode Lightning Wallet",
            "wallet_exists": wallet_exists,
            "wallet_logged_in": wallet_logged_in,
            "status": status,
            "message": message
        }
        return render_template('lnd.html', **templateData)

    if not is_lnd_logged_in():
        templateData = {
            "title": "myNode Lightning Wallet",
            "wallet_exists": wallet_exists,
            "wallet_logged_in": wallet_logged_in,
            "status": get_lnd_status(),
            "message": message
        }
        return render_template('lnd.html', **templateData)

    try:
        data = get_lightning_info()

        height = data['block_height']
        alias = data['alias']
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
    except Exception as e:
        templateData = {
            "title": "myNode Lightning Status",
            "message": str(e)
        }
        return render_template('lnd_error.html', **templateData)

    templateData = {
        "title": "myNode Lightning Status",
        "wallet_exists": wallet_exists,
        "wallet_logged_in": wallet_logged_in,
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
        "message": message
    }
    return render_template('lnd.html', **templateData)

@mynode_lnd.route("/lnd/tls.cert")
def lnd_tls_cert():
    return send_from_directory(directory="/mnt/hdd/mynode/lnd/", filename="tls.cert")

@mynode_lnd.route("/lnd/admin.macaroon", methods=["POST"])
def lnd_macaroon():
    p = pam.pam()
    pw = request.form.get('password_download_macaroon')
    if pw == None or p.authenticate("admin", pw) == False:
        return redirect(url_for(".page_lnd", error_message="Invalid Password"))

    # Download macaroon
    return send_from_directory(directory="/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/", filename="admin.macaroon")

@mynode_lnd.route("/lnd/create_wallet")
def page_lnd_create_wallet():

    try:
        seed = gen_new_wallet_seed()
        session['seed'] = seed.strip()
    except:
        templateData = {
            "title": "myNode Lightning Wallet",
            "message": Markup("Waiting on lnd...<br/>Please try again in a minute.")
        }
        return render_template('lnd_error.html', **templateData)

    templateData = {
        "title": "myNode Lightning Wallet",
        "seed": seed
    }
    return render_template('lnd_wallet_create.html', **templateData)

@mynode_lnd.route("/lnd/create_wallet_with_seed", methods=['GET','POST'])
def page_lnd_create_wallet_with_seed():
    # Load page
    if request.method == 'GET':
        templateData = {
            "title": "myNode Lightning Wallet",
        }
        return render_template('lnd_wallet_create_with_seed.html', **templateData)

    # Create wallet!
    seed = request.form.get('seed').strip()
    if create_wallet(seed):
        return redirect(url_for(".page_lnd", success_message="Wallet Created!"))
    
    # Error creating wallet
    return redirect(url_for(".page_lnd", error_message="Error Creating Wallet"))


@mynode_lnd.route("/lnd/create_wallet_confirm", methods=['GET','POST'])
def page_lnd_create_wallet_confirm():
    # Load page
    if request.method == 'GET':
        templateData = {
            "title": "myNode Lightning Wallet",
        }
        return render_template('lnd_wallet_create_confirm.html', **templateData)

    # Parse submission
    seed = request.form.get('seed').strip()
    if seed != session['seed']:
        session["seed"] = None
        return redirect(url_for(".page_lnd", error_message="Incorrect Seed"))
    session["seed"] = None

    # Seed matches, create wallet!
    if create_wallet(seed):
        return redirect(url_for(".page_lnd", success_message="Wallet Created!"))
    
    # Error creating wallet
    return redirect(url_for(".page_lnd", error_message="Error Creating Wallet"))
