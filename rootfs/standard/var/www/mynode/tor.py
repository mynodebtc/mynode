from flask import Blueprint, render_template, session, abort, Markup, request, redirect
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
from device_info import is_community_edition
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
    services.append({"service":"myNode Web","address":mynode_onion_hostname,"port": "80","password":mynode_onion_password})
    services.append({"service":"LND Hub","address":mynode_onion_hostname,"port": "3000","password":mynode_onion_password})
    services.append({"service":"BTC RPC Explorer","address":mynode_onion_hostname,"port": "3002","password":mynode_onion_password})
    services.append({"service":"LND Admin","address":mynode_onion_hostname,"port": "3004","password":mynode_onion_password})
    services.append({"service":"Ride the Lightning","address":mynode_onion_hostname,"port": "3010","password":mynode_onion_password})
    services.append({"service":"LND API (gRPC)","address":mynode_onion_hostname,"port": "10009","password":mynode_onion_password})
    services.append({"service":"LND API (REST)","address":mynode_onion_hostname,"port": "10080","password":mynode_onion_password})
    services.append({"service":"Electrum Server","address":mynode_onion_hostname,"port": "50001","password":mynode_onion_password})
    services.append({"service":"Electrum Server","address":mynode_onion_hostname,"port": "50002","password":mynode_onion_password})
    
    # Load page
    templateData = {
        "title": "myNode Tor Services",
        "mynode_onion_hostname": mynode_onion_hostname,
        "mynode_onion_password": mynode_onion_password,
        "services": services
    }
    return render_template('tor.html', **templateData)
