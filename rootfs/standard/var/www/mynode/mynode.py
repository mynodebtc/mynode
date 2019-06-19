
from config import *
from flask import Flask, render_template, Markup, send_from_directory, redirect, request
from bitcoind import mynode_bitcoind
from bitcoin_cli import mynode_bitcoin_cli
if CONFIG["electrs_enabled"]:
    from electrum_server import *
from lnd import mynode_lnd, lnd_wallet_exists, is_lnd_logged_in, lnd_get, get_lnd_status
from settings import mynode_settings
from pprint import pprint
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from background_thread import BackgroundThread
from prometheus_client.parser import text_string_to_metric_families
from bitcoin_info import *
from lightning_info import *
from messages import get_message
from thread_functions import *
import random
import logging
import logging.handlers
import requests
import threading
import signal
import transmissionrpc
import subprocess
import os.path
import psutil
import time

app = Flask(__name__)
app.config['DEBUG'] = False
app.config['TEMPLATES_AUTO_RELOAD'] = True
app.register_blueprint(mynode_bitcoind)
app.register_blueprint(mynode_lnd)
app.register_blueprint(mynode_bitcoin_cli)
if CONFIG["electrs_enabled"]:
    app.register_blueprint(mynode_electrum_server)
app.register_blueprint(mynode_settings)

### Definitions
STATE_DRIVE_MISSING =       "drive_missing"
STATE_DRIVE_MOUNTED =       "drive_mounted"
STATE_QUICKSYNC_DOWNLOAD =  "quicksync_download"
STATE_QUICKSYNC_COPY =      "quicksync_copy"
STATE_QUICKSYNC_RESET =      "quicksync_reset"
STATE_STABLE =              "stable"

MYNODE_DIR =    "/mnt/hdd/mynode"
BITCOIN_DIR =   "/mnt/hdd/mynode/bitcoin"
LN_DIR =        "/mnt/hdd/mynode/lnd"

### Global Variables
need_to_stop = False

### Helper functions
def get_status():
    status_file = "/mnt/hdd/mynode/.mynode_status"
    status = ""
    if (os.path.isfile(status_file)):
        try:
            with open(status_file, "r") as f:
                status = f.read().strip()
        except:
            status = STATE_DRIVE_MISSING
    else:
        status = STATE_DRIVE_MISSING
    return status


# Exception to throw on exit
class ServiceExit(Exception):
    pass

# Function to run on exit
def on_shutdown(signum, frame):
    print('Caught signal %d' % signum)
    raise ServiceExit


### Flask Page Processing
@app.route("/")
def index():
    status = get_status()

    bitcoin_block_height = get_bitcoin_block_height()
    mynode_block_height = get_mynode_block_height()
    lnd_info = get_lightning_info()
    pk_skipped = skipped_product_key()
    pk_error = not is_valid_product_key()

    # Show product key page if key not set
    if not has_product_key() and not skipped_product_key():
        return redirect("/product-key")
    
    if status == STATE_DRIVE_MISSING:
        templateData = {
            "title": "myNode Looking for Drive",
            "header_text": "Looking for Drive",
            "subheader_text": "Please attach a drive to your myNode"
        }
        return render_template('state.html', **templateData)
    elif status == STATE_DRIVE_MOUNTED:
        templateData = {
            "title": "myNode QuickSync",
            "header_text": "Drive Mounted",
            "subheader_text": "myNode starting soon..."
        }
        return render_template('state.html', **templateData)
    elif status == STATE_QUICKSYNC_COPY:
        try:
            current = subprocess.check_output(["du","-m","--max-depth=0","/mnt/hdd/mynode/bitcoin/"]).split()[0]
            total = subprocess.check_output(["du","-m","--max-depth=0","/mnt/hdd/mynode/quicksync/"]).split()[0]
        except:
            current = 0.0
            total = 100.0

        total = float(total) * 1.3
        percent = (float(current) / float(total)) * 100.0
        if percent >= 99.99:
            percent = 99.99

        message = "<div class='small_message'>{}</<div>".format( get_message() )

        subheader_msg = Markup("Copying files... This will take several hours.<br/>{:.2f}%{}".format(percent, message))

        templateData = {
            "title": "myNode QuickSync",
            "header_text": "QuickSync",
            "subheader_text": subheader_msg
        }
        return render_template('state.html', **templateData)
    elif status == STATE_QUICKSYNC_RESET:
        templateData = {
            "title": "myNode QuickSync",
            "header_text": "QuickSync",
            "subheader_text": "Restarting QuickSync..."
        }
        return render_template('state.html', **templateData)
    elif status == STATE_QUICKSYNC_DOWNLOAD:
        subheader = Markup("")
        try:
            tc = transmissionrpc.Client('localhost', port=9091)
            t = tc.get_torrent(1)

            dl_rate = float(t.rateDownload) / 1000 / 1000
            complete = t.percentDone * 100

            include_funny = False
            if dl_rate > 3.0:
                include_funny = True
            message = "<div class='small_message'>{}</<div>".format( get_message(include_funny) )

            subheader = Markup("Downloading...<br/>{:.2f}%</br>{:.2f} MB/s{}".format(complete, dl_rate, message))
        except Exception as e:
            subheader = Markup("Starting<br/>Waiting on download client to start...")

        templateData = {
            "title": "myNode QuickSync",
            "header_text": "QuickSync",
            "subheader_text": subheader
        }
        return render_template('state.html', **templateData)
    elif status == STATE_STABLE:
        bitcoind_status_code = os.system("systemctl status bitcoind --no-pager")
        lnd_status_code = os.system("systemctl status lnd --no-pager")
        bitcoind_status_color = "red"
        lnd_status_color = "red"
        lnd_ready = is_lnd_ready()
        rtl_status_color = "gray"
        rtl_status = "Lightning Wallet"
        lnd_admin_status_color = "gray"
        lnd_admin_status = "Lightning Wallet"
        electrs_status_color = "gray"
        lndhub_status_color = "gray"
        bitcoind_status = "Inactive"
        lnd_status = "Inactive"
        electrs_status = ""
        explorer_status = ""
        explorer_ready = False
        explorer_status_color = "red"
        btcrpcexplorer_status = ""
        btcrpcexplorer_ready = False
        btcrpcexplorer_status_color = "gray"

        if not get_has_updated_btc_info():
            message = "<div class='small_message'>{}</<div>".format( get_message(include_funny=True) )
            templateData = {
                "title": "myNode Status",
                "header_text": "Starting...",
                "subheader_text": Markup("Launching myNode services...{}".format(message))
            }
            return render_template('state.html', **templateData)

        # Display sync info if not synced
        if not is_bitcoind_synced():
            subheader = Markup("Syncing...")
            if bitcoin_block_height != None:
                message = "<div class='small_message'>{}</<div>".format( get_message(include_funny=True) )

                remaining = bitcoin_block_height - mynode_block_height
                subheader = Markup("Syncing...<br/>Block {} of {}{}".format(mynode_block_height, bitcoin_block_height, message))
            templateData = {
                "title": "myNode Sync",
                "header_text": "Bitcoin Blockchain",
                "subheader_text": subheader
            }
            return render_template('state.html', **templateData)

        # Find bitcoind status
        if bitcoind_status_code != 0:
            bitcoind_status_color = "red"
        else:
            bitcoind_status = "Validating blocks..."
            bitcoind_status_color = "green"
            if bitcoin_block_height != None:
                remaining = bitcoin_block_height - mynode_block_height
                if remaining == 0:
                    bitcoind_status = "Running"
                else:
                    bitcoind_status = "Syncing<br/>{} blocks remaining...".format(remaining)
            else:
                bitcoind_status = "Waiting for info..."

        # Find lnd status
        if is_bitcoind_synced():
            lnd_status_color = "green"
            lnd_status = get_lnd_status()
            
            # Get LND status
            if not lnd_wallet_exists():
                # This hides the restart /login attempt LND does from the GUI
                lnd_status_color = "green"
            elif lnd_status_code != 0:
                lnd_status_color = "red"
                if lnd_status == "Logging in...":
                    lnd_status_color = "yellow"
        else:
            lnd_status_color = "yellow"
            lnd_status = "Waiting..."

        # Find lndhub status
        if is_lndhub_enabled():
            if lnd_ready:
                status = os.system("systemctl status lndhub --no-pager")
                if status != 0:
                    lndhub_status_color = "red"
                else:
                    lndhub_status_color = "green"
            else:
                lndhub_status_color = "green"

        # Find RTL status
        if lnd_ready:
            status = os.system("systemctl status rtl --no-pager")
            if status != 0:
                rtl_status_color = "red"
            else:
                rtl_status_color = "green"

        # Find LND Admin Status
        if lnd_ready:
            status = os.system("systemctl status lnd_admin --no-pager")
            if status != 0:
                lnd_admin_status_color = "red"
            else:
                lnd_admin_status_color = "green"


        # Find electrs status
        if CONFIG["electrs_enabled"]:
            if is_electrs_enabled():
                status = os.system("systemctl status electrs --no-pager")
                if status != 0:
                    electrs_status_color = "red"
                else:
                    electrs_status_color = "green"
                    electrs_status = get_electrs_status()

        # Find btc-rpc-explorer status
        if CONFIG["btcrpcexplorer_enabled"]:
            btcrpcexplorer_status = "BTC RPC Explorer"
            if is_btcrpcexplorer_enabled():
                status = os.system("systemctl status btc_rpc_explorer --no-pager")
                if status != 0:
                    btcrpcexplorer_status_color = "red"
                else:
                    btcrpcexplorer_status_color = "green"

        # Find explorer status
        if CONFIG["explorer_enabled"]:
            explorer_status_color = electrs_status_color
            if is_electrs_enabled():
                if is_electrs_active():
                    explorer_ready = True
                    explorer_status = "myNode BTC Explorer"
                else:
                    explorer_status = Markup("Bitcoin Explorer<br/><br/>Waiting on Electrum Server...")
            else:
                explorer_status = Markup("Bitcoin Explorer<br/><br/>Requires Electrum Server")

        # Check for new version of software
        upgrade_available = False
        current = get_current_version()
        latest = get_latest_version()
        if current != "0.0" and latest != "0.0" and current != latest:
            upgrade_available = True


        templateData = {
            "title": "myNode Home",
            "config": CONFIG,
            "bitcoind_status_color": bitcoind_status_color,
            "bitcoind_status": Markup(bitcoind_status),
            "lnd_status_color": lnd_status_color,
            "lnd_status": Markup(lnd_status),
            "lnd_ready": lnd_ready,
            "electrs_status_color": electrs_status_color,
            "electrs_status": Markup(electrs_status),
            "electrs_enabled": is_electrs_enabled(),
            "rtl_status_color": rtl_status_color,
            "rtl_status": rtl_status,
            "lnd_admin_status_color": lnd_admin_status_color,
            "lnd_admin_status": lnd_admin_status,
            "lndhub_status_color": lndhub_status_color,
            "lndhub_enabled": is_lndhub_enabled(),
            "explorer_ready": explorer_ready,
            "explorer_status_color": explorer_status_color,
            "explorer_status": explorer_status,
            "btcrpcexplorer_ready": btcrpcexplorer_ready,
            "btcrpcexplorer_status_color": btcrpcexplorer_status_color,
            "btcrpcexplorer_status": btcrpcexplorer_status,
            "btcrpcexplorer_enabled": is_btcrpcexplorer_enabled(),
            "product_key_skipped": pk_skipped,
            "product_key_error": pk_error,
            "drive_usage": get_drive_usage(),
            "cpu_usage": get_cpu_usage(),
            "ram_usage": get_ram_usage(),
            "swap_usage": get_swap_usage(),
            "upgrade_available": upgrade_available
        }
        return render_template('main.html', **templateData)
    else:
        templateData = {
            "title": "myNode Error",
            "header_text": "Error",
            "subheader_text": "Unknown State ("+status+"). Please restart your myNode."
        }
        return render_template('state.html', **templateData)

@app.route("/product-key", methods=['GET','POST'])
def page_product_key():
    # If get, just display page
    if request.method == 'GET':
        templateData = {
            "title": "myNode Product Key",
            "header_text": "Product Key"
        }
        return render_template('product_key.html', **templateData)
    elif request.method == 'POST':
        skip = request.form.get('pk_skip')
        submit = request.form.get('pk_submit')
        product_key = request.form.get('product_key')

        # Skip product key, redirect to home page
        # Community edition was chosen!
        if skip != None:
            delete_product_key_error()
            set_skipped_product_key()
            return redirect("/")
        
        # Save product key
        if submit != None and product_key != None:
            unset_skipped_product_key()
            delete_product_key_error()

            save_product_key(product_key)

            t = Timer(10.0, check_in)
            t.start()

            return redirect("/")

        return "Error"
    

@app.route("/toggle-lndhub")
def page_toggle_lndhub():
    if is_lndhub_enabled():
        disable_lndhub()
    else:
        enable_lndhub()
    return redirect("/")

@app.route("/toggle-electrs")
def page_toggle_electrs():
    if is_electrs_enabled():
        disable_electrs()
    else:
        enable_electrs()
    return redirect("/")

@app.route("/toggle-btcrpcexplorer")
def page_toggle_btcrpcexplorer():
    if is_btcrpcexplorer_enabled():
        disable_btcrpcexplorer()
    else:
        enable_btcrpcexplorer()
    return redirect("/")

@app.route("/about")
def page_about():
    return render_template('about.html')

@app.route("/help")
def page_help():
    return render_template('help.html')

# Disable browser caching
@app.after_request
def set_response_headers(response):
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, on_shutdown)
    signal.signal(signal.SIGINT, on_shutdown)
    btc_thread1 = BackgroundThread(update_bitcoin_main_info_thread, 60)
    btc_thread1.start()
    btc_thread2 = BackgroundThread(update_bitcoin_other_info_thread, 60)
    btc_thread2.start()
    electrs_info_thread = BackgroundThread(update_electrs_info_thread, 60)
    electrs_info_thread.start()
    lnd_thread = BackgroundThread(update_lnd_info_thread, 60)
    lnd_thread.start()
    drive_thread = BackgroundThread(update_device_info, 60)
    drive_thread.start()
    checkin_thread = BackgroundThread(check_in, 60*60*24) # Per-day checkin
    checkin_thread.start()

    my_logger = logging.getLogger('FlaskLogger')
    my_logger.setLevel(logging.DEBUG)
    handler = logging.handlers.RotatingFileHandler(filename='/var/log/flask', maxBytes=2000000, backupCount=2)
    my_logger.addHandler(handler)
    app.logger.addHandler(my_logger)

    app.secret_key = 'NoZlPx7t15foPfKpivbVrTrTy2bTQ99chJoz3LFmf5BFsh3Nz4ud0mMpGjtB4bhP'

    try:
        app.run(host='0.0.0.0', port=80)
    except ServiceExit:
        # Stop background thread
        print("Killing {}".format(btc_thread1.pid))
        os.kill(btc_thread1.pid, signal.SIGKILL)
        print("Killing {}".format(btc_thread2.pid))
        os.kill(btc_thread2.pid, signal.SIGKILL)
        print("Killing {}".format(electrs_info_thread.pid))
        os.kill(electrs_info_thread.pid, signal.SIGKILL)
        print("Killing {}".format(lnd_thread.pid))
        os.kill(lnd_thread.pid, signal.SIGKILL)
        print("Killing {}".format(drive_thread.pid))
        os.kill(drive_thread.pid, signal.SIGKILL)

        # Shutdown Flask
        func = request.environ.get('werkzeug.server.shutdown')
        if func is None:
            raise RuntimeError('Not running with the Werkzeug Server')
        func()

    print("Service www exiting...")