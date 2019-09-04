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
    electrs_onion_hostname = "..."
    electrs_onion_command = "..."
    lnd_onion_hostname = "..."
    lnd_onion_password = "..."

    # Check if we are premium
    if is_community_edition():
        return redirect("/")

    # Get Onion URLs
    try:
        if os.path.isfile("/var/lib/tor/electrs_hidden_service/hostname"):
            with open("/var/lib/tor/electrs_hidden_service/hostname") as f:
                electrs_onion_hostname = f.read().strip()
                electrs_onion_command = "./electrum -1 -s {}:50002:s -p socks5:localhost:9050".format(electrs_onion_hostname)
        else:
            electrs_onion_hostname = "disabled"
            electrs_onion_command = "disabled"

        if os.path.isfile("/var/lib/tor/lnd_api/hostname"):
            with open("/var/lib/tor/lnd_api/hostname") as f:
                contents = f.read().split()
                lnd_onion_hostname = contents[0]
                lnd_onion_password = contents[1]
    except:
        electrs_onion_hostname = "error"
        lnd_onion_hostname = "error"


    # Load page
    templateData = {
        "title": "myNode Tor Services",
        "electrs_onion_hostname": electrs_onion_hostname,
        "electrs_onion_command": electrs_onion_command,
        "lnd_onion_hostname": lnd_onion_hostname,
        "lnd_onion_password": lnd_onion_password
    }
    return render_template('tor.html', **templateData)
