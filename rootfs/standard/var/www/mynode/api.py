
from flask import Blueprint, render_template, redirect, jsonify, request
from user_management import check_logged_in
from bitcoin_info import *
from lightning_info import *
from electrum_info import *
from device_info import *
from dojo import get_dojo_status
import subprocess
import re
import os

mynode_api = Blueprint('mynode_api',__name__)


### Page functions
@mynode_api.route("/api/get_bitcoin_info")
def api_get_bitcoin_info():
    check_logged_in()

    data = {}
    data["current_block"] = get_mynode_block_height()
    data["peer_count"] = get_bitcoin_peer_count()
    data["difficulty"] = get_bitcoin_difficulty()
    data["mempool_size"] = get_bitcoin_mempool_size()

    # Add blocks
    data["recent_blocks"] = None
    blocks = get_bitcoin_recent_blocks()
    if blocks != None:
        for b in blocks:
            # Remove TX list for faster processing
            b["tx"] = None
        data["recent_blocks"] = blocks

    return jsonify(data)

@mynode_api.route("/api/get_lightning_info")
def api_get_lightning_info():
    check_logged_in()

    data = {}
    data["peer_count"] = get_lightning_peer_count()
    data["channel_count"] = get_lightning_channel_count()

    return jsonify(data)

@mynode_api.route("/api/get_service_status")
def api_get_service_status():
    check_logged_in()

    data = {}
    data["status"] = ""
    data["color"] = ""

    service = request.args.get('service')
    if service == "electrs":
        status_code = get_service_status_code("electrs")
        if status_code == 0:
            data["status"] = get_electrs_status()
            data["color"] = get_service_status_color("electrs")
        else:
            data["status"] = "error"
            data["color"] = "red"
    elif service == "bitcoin":
        if get_service_status_code("bitcoind") == 0:
            data["status"] = get_bitcoin_status()
            data["color"] = "green"
        else:
            data["status"] = "error"
            data["color"] = "red"
    elif service == "lightning":
        data["status"] = get_lnd_status()
        data["color"] = get_lnd_status_color()
    elif service == "dojo":
        dojo_status, dojo_status_color, dojo_initialized = get_dojo_status()
        data["status"] = dojo_status
        data["color"] = dojo_status_color
        if is_installing_docker_images():
            dojo_status_color = "yellow"
            dojo_status = "Installing..."
    else:
        data["status"] = "unknown service"

    return jsonify(data)
