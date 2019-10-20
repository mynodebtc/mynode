from flask import Blueprint, render_template, session, abort, Markup, request, redirect
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
from device_info import is_community_edition
from settings import read_ui_settings
import os
import json
import time
import subprocess

mynode_tor = Blueprint('mynode_tor',__name__)

### Page functions
@mynode_tor.route("/tor")
def page_tor():
    mynode_onion_hostname = "..."
    mynode_onion_password = "..."

    # Check if we are premium
    if is_community_edition():
        return redirect("/")

    # Get Onion URLs
    try:
        if os.path.isfile("/var/lib/tor/mynode/hostname"):
            with open("/var/lib/tor/mynode/hostname") as f:
                contents = f.read().split()
                mynode_onion_hostname = contents[0]
                mynode_onion_password = contents[1]
    except:
        mynode_onion_hostname = "error"
        mynode_onion_password = "error"

    services = []
    services.append({"service":"myNode Web","port": "80","guide":""})
    services.append({"service":"LND Hub","port": "3000","guide":""})
    services.append({"service":"BTC RPC Explorer","port": "3002","guide":""})
    services.append({"service":"LND Admin","port": "3004","guide":""})
    services.append({"service":"Ride the Lightning","port": "3010","guide":""})
    services.append({"service":"Bitcoin API (REST)","port": "8332","guide":""})
    services.append({"service":"LND API (gRPC)","port": "10009","guide":""})
    services.append({"service":"LND API (REST)","port": "10080","guide":""})
    services.append({"service":"Electrum Server","port": "50001","guide":"https://mynodebtc.com/guide/electrum_server_tor"})
    services.append({"service":"Electrum Server","port": "50002","guide":"https://mynodebtc.com/guide/electrum_server_tor"})
    
    # Load page
    templateData = {
        "title": "myNode Tor Services",
        "mynode_onion_hostname": mynode_onion_hostname,
        "mynode_onion_password": mynode_onion_password,
        "services": services,
        "ui_settings": read_ui_settings()
    }
    return render_template('tor.html', **templateData)
