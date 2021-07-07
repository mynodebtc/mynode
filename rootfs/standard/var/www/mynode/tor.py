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

def create_v3_service(name, url, port, show_link, guide, force_https=False):
    service = {}
    service["service"] = name
    service["id"] = name.replace(" ","").replace("(","").replace(")","").lower()
    service["url"] = url
    service["port"] = port
    service["show_link"] = show_link
    service["link"] = ""
    if show_link:
        try:
            if "/" in port:
                p = port.split("/")[1].strip()
                service["link"] = "https://"+url+":"+p
            else:
                if force_https:
                    service["link"] = "https://"+url+":"+port
                else:
                    service["link"] = "http://"+url+":"+port
        except:
            service["link"] = "URL_ERROR"
    service["guide"] = guide
    return service

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
    lndhub_onion_url = get_onion_url_lndhub()
    lnbits_onion_url = get_onion_url_lnbits()
    electrs_onion_url = get_onion_url_electrs()
    btcpay_onion_url = get_onion_url_btcpay()
    sphinxrelay_onion_url = get_onion_url_sphinxrelay()

    btc_info_v2 = get_onion_info_btc_v2()


    # Services
    v3_services = []
    v3_services.append(create_v3_service("myNode Web", general_onion_url, "80", True, ""))
    v3_services.append(create_v3_service("WebSSH", general_onion_url, "2222 / 2223", True, ""))
    v3_services.append(create_v3_service("LND Hub", lndhub_onion_url, "3000 / 3001", True, ""))
    v3_services.append(create_v3_service("BTC RPC Explorer", general_onion_url, "3002 / 3003", False, ""))
    v3_services.append(create_v3_service("Ride the Lightning", general_onion_url, "3010 / 3011", True, ""))
    v3_services.append(create_v3_service("Caravan", general_onion_url, "3020", True, ""))
    v3_services.append(create_v3_service("Thunderhub", general_onion_url, "3030 / 3031", True, ""))
    v3_services.append(create_v3_service("Mempool", general_onion_url, "4080 / 4081", True, ""))
    v3_services.append(create_v3_service("LNbits", lnbits_onion_url, "5000 / 5001", True, ""))
    v3_services.append(create_v3_service("Lightning Terminal", general_onion_url, "8443", True, ""))
    v3_services.append(create_v3_service("Whirlpool", general_onion_url, "8899", False, ""))
    v3_services.append(create_v3_service("Netdata", general_onion_url, "19999 / 20000", True, ""))
    v3_services.append(create_v3_service("Specter Desktop", general_onion_url, "25441", True, "", force_https=True))
    v3_services.append(create_v3_service("Glances", general_onion_url, "61208 / 61209", True, ""))
    v3_services.append(create_v3_service("BTCPay Server", btcpay_onion_url, "49392 / 49393", True, ""))
    v3_services.append(create_v3_service("Bitcoin API (REST)", btc_onion_url, "8332", False, ""))
    v3_services.append(create_v3_service("LND API (gRPC)", lnd_onion_url, "10009", False, ""))
    v3_services.append(create_v3_service("LND API (REST)", lnd_onion_url, "10080", False, ""))
    v3_services.append(create_v3_service("SSH", ssh_onion_url, "22022", False, ""))
    v3_services.append(create_v3_service("Electrum Server", electrs_onion_url, "50001", False, "https://mynodebtc.github.io/tor/electrum.html"))
    v3_services.append(create_v3_service("Electrum Server", electrs_onion_url, "50002", False, "https://mynodebtc.github.io/tor/electrum.html"))
    v3_services.append(create_v3_service("Sphinx Relay", sphinxrelay_onion_url, "53001", True, ""))
    
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
