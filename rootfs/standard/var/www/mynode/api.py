
from flask import Blueprint, render_template, redirect, jsonify, request
from flask import current_app as app
from user_management import check_logged_in
from bitcoin_info import *
from lightning_info import *
from electrum_info import *
from device_info import *
from dojo import get_dojo_status
from whirlpool import get_whirlpool_status
from thread_functions import *
from systemctl_info import *
import json
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
    #data["difficulty"] = get_bitcoin_difficulty() # Dont send difficulty, it causes errors in jsonify
    data["mempool_size"] = get_bitcoin_mempool_size()

    # Add blocks
    data["recent_blocks"] = None
    blocks = get_bitcoin_recent_blocks()
    if blocks != None:
        for b in blocks:
            # Remove TX list for faster processing
            b["tx"] = None
            # Remove difficulty since JSON can't parse large floats (???)
            b["difficulty"] = None
        data["recent_blocks"] = blocks

    #app.logger.info("api_get_bitcoin_info data: "+json.dumps(data))
    return jsonify(data)

@mynode_api.route("/api/get_lightning_info")
def api_get_lightning_info():
    check_logged_in()

    data = {}
    data["peer_count"] = get_lightning_peer_count()
    data["channel_count"] = get_lightning_channel_count()
    data["lnd_ready"] = is_lnd_ready()
    data["channels"] = get_lightning_channels()

    return jsonify(data)

@mynode_api.route("/api/get_service_status")
def api_get_service_status():
    check_logged_in()

    data = {}
    data["status"] = "gray"
    data["color"] = ""
    data["ready"] = None

    service = request.args.get('service')
    if service == "electrs":
        data["status"], data["color"] = get_electrs_status_and_color()
    elif service == "bitcoin":
        data["status"], data["color"] = get_bitcoin_status_and_color()
    elif service == "lightning":
        data["status"], data["color"] = get_lnd_status_and_color()
    elif service == "dojo":
        data["status"], data["color"], dojo_initialized = get_dojo_status()
    elif service == "rtl":
        data["status"], data["color"] = get_rtl_status_and_color()
    elif service == "mempool":
        data["status"], data["color"] = get_mempool_status_and_color()
    elif service == "whirlpool":
        data["status"], data["color"], whirlpool_initialized = get_whirlpool_status()
    elif service == "btcpayserver":
        data["status"], data["color"] = get_btcpayserver_status_and_color()
    elif service == "lndhub":
        data["status"], data["color"] = get_lndhub_status_and_color()
    elif service == "btcrpcexplorer":
        data["status"], data["color"], data["ready"] = get_btcrpcexplorer_status_and_color_and_ready()
        data["sso_token"] = get_btcrpcexplorer_sso_token()
    elif service == "caravan":
        data["status"], data["color"] = get_caravan_status_and_color()
    elif service == "specter":
        data["status"], data["color"] = get_specter_status_and_color()
    elif service == "lnbits":
        data["status"], data["color"] = get_lnbits_status_and_color()
    elif service == "thunderhub":
        data["status"], data["color"] = get_thunderhub_status_and_color()
    elif service == "ckbunker":
        data["status"], data["color"] = get_ckbunker_status_and_color()
    elif service == "sphinxrelay":
        data["status"], data["color"] = get_sphinxrelay_status_and_color()
    elif service == "tor":
        data["status"] = "Private Connections"
        data["color"] = get_service_status_color("tor@default")
    elif service == "vpn":
        data["status"], data["color"] = get_vpn_status_and_color()
    else:
        data["status"] = "unknown service"

    return jsonify(data)

@mynode_api.route("/api/get_device_info")
def api_get_device_info():
    check_logged_in()

    data = {}
    data["disk_usage"] = get_drive_usage()
    data["cpu"] = get_cpu_usage()
    data["ram"] = get_ram_usage()
    data["temp"] = get_device_temp()
    data["is_installing_docker_images"] = is_installing_docker_images()

    return jsonify(data)

@mynode_api.route("/api/homepage_needs_refresh")
def api_homepage_needs_refresh():
    check_logged_in()

    data = {}
    data["needs_refresh"] = "no"

    if get_mynode_status() != STATE_STABLE:
        data["needs_refresh"] = "yes"
    if not has_product_key() and not skipped_product_key():
        data["needs_refresh"] = "yes"
    if not get_has_updated_btc_info():
        data["needs_refresh"] = "yes"
    if not is_bitcoind_synced():
        data["needs_refresh"] = "yes"

    return jsonify(data)