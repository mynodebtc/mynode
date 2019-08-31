from flask import Blueprint, render_template, session, abort, Markup, request, redirect
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
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

    # Get Onion URLs
    if os.path.isfile("/var/lib/tor/electrs_hidden_service/hostname"):
        with open("/var/lib/tor/electrs_hidden_service/hostname") as f:
            electrs_onion_hostname = f.read().strip()
            electrs_onion_command = "./electrum -1 -s {}:50001:t -p socks5:localhost:9050".format(electrs_onion_hostname)
    else:
        electrs_onion_hostname = "disabled"
        electrs_onion_command = "disabled"

    # Load page
    templateData = {
        "title": "myNode Tor Services",
        "electrs_onion_hostname": electrs_onion_hostname,
        "electrs_onion_command": electrs_onion_command
    }
    return render_template('tor.html', **templateData)
