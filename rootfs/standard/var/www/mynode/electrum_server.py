from flask import Blueprint, render_template, session, abort, Markup, request, redirect
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
from bitcoin_info import *
from device_info import get_local_ip, skipped_product_key, get_onion_url_electrs
from user_management import check_logged_in
from settings import read_ui_settings
from electrum_info import *
import json
import time

mynode_electrum_server = Blueprint('mynode_electrum_server',__name__)


### Page functions
@mynode_electrum_server.route("/electrum-server")
def electrum_server_page():
    check_logged_in()

    # Make sure data is up to date
    update_electrs_info()

    # Get latest info
    current_block = get_electrum_server_current_block()
    if current_block == None:
        current_block = "Unknown"
    status = get_electrs_status()

    #server_url = get_local_ip() + ":50002:s"
    server_ip = get_local_ip()
    server_standard_port = "50001"
    server_secure_port = "50002"

    # Get IP URLs
    electrs_command = "./electrum -1 -s {}:50002:s".format(server_ip)

    # Get Onion URLs
    electrs_onion_hostname = get_onion_url_electrs()
    electrs_onion_command = "./electrum -1 -s {}:50002:s -p socks5:localhost:9050".format(electrs_onion_hostname)


    # Load page
    templateData = {
        "title": "myNode Electrum Server",
        "port": 50002,
        "status": status,
        "product_key_skipped": skipped_product_key(),
        "current_block": current_block,
        #"server_url": server_url,
        "server_ip": server_ip,
        "server_standard_port": server_standard_port,
        "server_secure_port": server_secure_port,
        "electrs_command": electrs_command,
        "electrs_onion_hostname": electrs_onion_hostname,
        "electrs_onion_command": electrs_onion_command,
        "ui_settings": read_ui_settings()
    }
    return render_template('electrum_server.html', **templateData)
