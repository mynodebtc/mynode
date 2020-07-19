from flask import Blueprint, render_template, session, abort, Markup, request, redirect
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
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
    btcpay_onion_url = get_onion_url_btcpay()

    btc_info_v2 = get_onion_info_btc_v2()


    # Services
    v3_services = []
    v3_services.append({"service": "myNode Web", "url": general_onion_url, "port": "80","guide":""})
    v3_services.append({"service": "LND Hub", "url": general_onion_url,"port": "3000","guide":""})
    v3_services.append({"service": "BTC RPC Explorer", "url": general_onion_url,"port": "3002","guide":""})
    v3_services.append({"service": "Ride the Lightning", "url": general_onion_url,"port": "3010","guide":""})
    v3_services.append({"service": "Caravan", "url": general_onion_url,"port": "3020","guide":""})
    v3_services.append({"service": "LNbits", "url": general_onion_url,"port": "5000","guide":""})
    v3_services.append({"service": "Specter Desktop", "url": general_onion_url,"port": "25441","guide":""})
    v3_services.append({"service": "BTCPay Server", "url": btcpay_onion_url,"port": "49392","guide":""})
    v3_services.append({"service": "Bitcoin API (REST)", "url": btc_onion_url,"port": "8332","guide":""})
    v3_services.append({"service": "LND API (gRPC)", "url": lnd_onion_url,"port": "10009","guide":""})
    v3_services.append({"service": "LND API (REST)", "url": lnd_onion_url,"port": "10080","guide":""})
    v3_services.append({"service": "SSH", "url": ssh_onion_url, "port": "22022","guide":""})
    v3_services.append({"service": "Electrum Server", "url": electrs_onion_url,"port": "50001","guide":"https://mynodebtc.com/guide/electrum_server_tor"})
    v3_services.append({"service": "Electrum Server", "url": electrs_onion_url,"port": "50002","guide":"https://mynodebtc.com/guide/electrum_server_tor"})
    
    v2_services = []
    v2_services.append({"service": "Bitcoin API (REST)", "url": btc_info_v2["url"], "password": btc_info_v2["pass"], "port": "8332","guide":""})

    # App links
    rpc_password = get_bitcoin_rpc_password()
    fully_noded_link = "btcstandup://mynode:{}@{}:8332?label=myNode%20Tor".format(rpc_password, btc_onion_url)

    # Load page
    templateData = {
        "title": "myNode Tor Services",
        "version": get_tor_version(),
        "v3_services": v3_services,
        "v2_services": v2_services,
        "fully_noded_link": fully_noded_link,
        "ui_settings": read_ui_settings()
    }
    return render_template('tor.html', **templateData)
