from flask import Blueprint, render_template, session, abort, Markup, request, redirect
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
from settings import read_ui_settings
from device_info import *
from user_management import check_logged_in
import os
import json
import time
import subprocess

mynode_tor = Blueprint('mynode_tor',__name__)

### Page functions
@mynode_tor.route("/tor")
def page_tor():
    check_logged_in()

    # Check if we are premium
    if is_community_edition():
        return redirect("/")

    # Get Onion URLs
    ssh_onion_url = get_onion_url_ssh()
    general_onion_url = get_onion_url_general()
    btc_onion_url = get_onion_url_btc()
    lnd_onion_url = get_onion_url_lnd()
    electrs_onion_url = get_onion_url_electrs()

    # Services
    services = []
    services.append({"service": "myNode Web", "url": general_onion_url, "port": "80","guide":""})
    services.append({"service": "LND Hub", "url": general_onion_url,"port": "3000","guide":""})
    services.append({"service": "BTC RPC Explorer", "url": general_onion_url,"port": "3002","guide":""})
    services.append({"service": "Ride the Lightning", "url": general_onion_url,"port": "3010","guide":""})
    services.append({"service": "Bitcoin API (REST)", "url": btc_onion_url,"port": "8332","guide":""})
    services.append({"service": "LND API (gRPC)", "url": lnd_onion_url,"port": "10009","guide":""})
    services.append({"service": "LND API (REST)", "url": lnd_onion_url,"port": "10080","guide":""})
    services.append({"service": "SSH", "url": ssh_onion_url, "port": "22022","guide":""})
    services.append({"service": "Electrum Server", "url": electrs_onion_url,"port": "50001","guide":"https://mynodebtc.com/guide/electrum_server_tor"})
    services.append({"service": "Electrum Server", "url": electrs_onion_url,"port": "50002","guide":"https://mynodebtc.com/guide/electrum_server_tor"})
    
    # App links
    rpc_password = get_bitcoin_rpc_password()
    fully_noded_link = "btcrpc://mynode:{}@{}:8332?label=myNode%20Tor".format(rpc_password, btc_onion_url)

    # Load page
    templateData = {
        "title": "myNode Tor Services",
        "services": services,
        "fully_noded_link": fully_noded_link,
        "ui_settings": read_ui_settings()
    }
    return render_template('tor.html', **templateData)
