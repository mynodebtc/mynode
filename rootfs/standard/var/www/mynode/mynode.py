
from config import *
from flask import Flask, render_template, Markup, send_from_directory, redirect, request, url_for
from user_management import *
from bitcoind import mynode_bitcoind
from whirlpool import mynode_whirlpool, get_whirlpool_status
from dojo import mynode_dojo, get_dojo_status
from tor import mynode_tor
from vpn import mynode_vpn
from electrum_server import *
from lnd import mynode_lnd, lnd_wallet_exists, is_lnd_logged_in, lnd_get, get_lnd_status
from settings import *
from pprint import pprint
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from background_thread import BackgroundThread
from prometheus_client.parser import text_string_to_metric_families
from bitcoin_info import *
from lightning_info import *
from messages import get_message
from thread_functions import *
from datetime import timedelta
from device_info import *
import pam
import json
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
app.config['MAX_CONTENT_LENGTH'] = 32 * 1024 * 1024     # 32 MB upload file max
app.config['UPLOAD_FOLDER'] = "/tmp/flask_uploads"
app.register_blueprint(mynode_bitcoind)
app.register_blueprint(mynode_lnd)
app.register_blueprint(mynode_whirlpool)
app.register_blueprint(mynode_dojo)
app.register_blueprint(mynode_tor)
app.register_blueprint(mynode_electrum_server)
app.register_blueprint(mynode_vpn)
app.register_blueprint(mynode_settings)

### Definitions
STATE_DRIVE_MISSING =         "drive_missing"
STATE_DRIVE_CONFIRM_FORMAT =  "drive_format_confirm"
STATE_DRIVE_FORMATTING =      "drive_formatting"
STATE_DRIVE_MOUNTED =         "drive_mounted"
STATE_QUICKSYNC_DOWNLOAD =    "quicksync_download"
STATE_QUICKSYNC_COPY =        "quicksync_copy"
STATE_QUICKSYNC_RESET =       "quicksync_reset"
STATE_STABLE =                "stable"

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
    check_logged_in()
    status = get_status()

    bitcoin_block_height = get_bitcoin_block_height()
    mynode_block_height = get_mynode_block_height()
    uptime_in_seconds = get_system_uptime_in_seconds()
    pk_skipped = skipped_product_key()
    pk_error = not is_valid_product_key()

    # Show uploader page if we are marked as an uploader
    if is_uploader():
        status=""
        try:
            status = subprocess.check_output(["mynode-get-quicksync-status"])
        except:
            status = "Waiting on quicksync to start..."

        status = status.decode("utf8")
        status = Markup("<div style='text-align: left; font-size: 12px; width: 800px;'><pre>"+status+"</pre></div>")
        templateData = {
            "title": "myNode Uploader",
            "header_text": "Uploader Device",
            "quicksync_status": status,
            "ui_settings": read_ui_settings()
        }
        return render_template('uploader.html', **templateData)

    if status == STATE_DRIVE_MISSING:

        # Drive may be getting repaired
        if is_drive_being_repaired():
            templateData = {
                "title": "myNode Repairing Drive",
                "header_text": "Repairing Drive",
                "subheader_text": Markup("Drive is being checked and repaired...<br/><br/>This will take several hours."),
                "ui_settings": read_ui_settings()
            }
            return render_template('state.html', **templateData)

        templateData = {
            "title": "myNode Looking for Drive",
            "header_text": "Looking for Drive",
            "subheader_text": "Please attach a drive to your myNode",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_DRIVE_CONFIRM_FORMAT:
        if request.args.get('format'):
            os.system("touch /tmp/format_ok")
            time.sleep(1)
            return redirect("/")

        templateData = {
            "title": "myNode Confirm Drive Format",
            "ui_settings": read_ui_settings()
        }
        return render_template('confirm_drive_format.html', **templateData)
    elif status == STATE_DRIVE_FORMATTING:
        templateData = {
            "title": "myNode Drive Formatting",
            "header_text": "Drive Formatting",
            "subheader_text": "myNode is preparing the drive for use...",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_DRIVE_MOUNTED:
        templateData = {
            "title": "myNode Drive Mounted",
            "header_text": "Drive Mounted",
            "subheader_text": "myNode starting soon...",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif not has_product_key() and not skipped_product_key():
        # Show product key page if key not set
        return redirect("/product-key")
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
            "subheader_text": subheader_msg,
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_QUICKSYNC_RESET:
        templateData = {
            "title": "myNode QuickSync",
            "header_text": "QuickSync",
            "subheader_text": "Restarting QuickSync...",
            "ui_settings": read_ui_settings()
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
            "subheader_text": subheader,
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_STABLE:
        bitcoind_status_code = get_service_status_code("bitcoind")
        lnd_status_code = get_service_status_code("lnd")
        tor_status_color = "gray"
        bitcoind_status_color = "red"
        lnd_status_color = "red"
        lnd_ready = is_lnd_ready()
        rtl_status_color = "gray"
        rtl_status = "Lightning Wallet"
        electrs_status_color = "gray"
        lndhub_status_color = "gray"
        bitcoind_status = "Inactive"
        lnd_status = "Inactive"
        electrs_status = ""
        explorer_status = ""
        explorer_ready = False
        explorer_status_color = "red"
        lndconnect_status_color = "gray"
        btcpayserver_status_color = "gray"
        btcrpcexplorer_status = ""
        btcrpcexplorer_ready = False
        btcrpcexplorer_status_color = "gray"
        mempoolspace_status_color = "gray"
        vpn_status_color = "gray"
        vpn_status = ""

        if not get_has_updated_btc_info() or uptime_in_seconds < 150:
            error_message = ""
            if bitcoind_status_code != 0 and uptime_in_seconds > 300:
                error_message = "Bitcoin has experienced an error. Please check the logs."
            message = "<div class='small_message'>{}</<div>".format( get_message(include_funny=True) )
            templateData = {
                "title": "myNode Status",
                "header_text": "Starting...",
                "subheader_text": Markup("Launching myNode services...{}".format(message)),
                "error_message": error_message,
                "ui_settings": read_ui_settings()
            }
            return render_template('state.html', **templateData)

        # if is_installing_docker_images():
        #     message = "<div class='small_message'>{}</<div>".format( get_message(include_funny=True) )
        #     templateData = {
        #         "title": "myNode Status",
        #         "header_text": "Starting...",
        #         "subheader_text": Markup("Building Docker Images...{}".format(message)),
        #         "ui_settings": read_ui_settings()
        #     }
        #     return render_template('state.html', **templateData)

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
                "subheader_text": subheader,
                "ui_settings": read_ui_settings()
            }
            return render_template('state.html', **templateData)

        # Find tor status
        tor_status_color = get_service_status_color("tor@default")

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
                lndhub_status_color = get_service_status_color("lndhub")

        # Find RTL status
        if lnd_ready:
            status_code = get_service_status_code("rtl")
            if status_code != 0:
                rtl_status_color = "red"
            else:
                rtl_status_color = "green"

        # Find electrs status
        if is_electrs_enabled():
            status_code = get_service_status_code("electrs")
            electrs_status_color = get_service_status_color("electrs")
            if status_code == 0:
                electrs_status = get_electrs_status()

        # Find btc-rpc-explorer status
        btcrpcexplorer_status = "BTC RPC Explorer"
        if is_btcrpcexplorer_enabled():
            if is_bitcoind_synced():
                if is_electrs_active():
                    btcrpcexplorer_status_color = get_service_status_color("btc_rpc_explorer")
                    status_code = get_service_status_code("btc_rpc_explorer")
                    if status_code == 0:
                        btcrpcexplorer_ready = True
                else:
                    btcrpcexplorer_status_color = "green"
                    btcrpcexplorer_status = "Waiting on electrs..."
            else:
                btcrpcexplorer_status_color = "gray"
                btcrpcexplorer_status = "Waiting on bitcoin..."

        # Find mempool space status
        mempoolspace_status = "Mempool Viewer"
        if is_mempoolspace_enabled():
            if is_installing_docker_images():
                mempoolspace_status_color = "yellow"
                mempoolspace_status = "Installing..."
            else:
                mempoolspace_status_color = get_service_status_color("mempoolspace")

        # Find lndconnect status
        if lnd_ready:
            lndconnect_status_color = "green"

        # Find btcpayserver status
        btcpayserver_status = "Merchant Tool"
        if lnd_ready:
            btcpayserver_status_color = get_service_status_color("btcpayserver")
        else:
            btcpayserver_status = "Waiting on LND..."

        # Find explorer status
        explorer_status_color = electrs_status_color
        if is_electrs_enabled():
            if is_electrs_active():
                explorer_ready = True
                explorer_status = "myNode BTC Explorer"
            else:
                explorer_status = Markup("Bitcoin Explorer<br/><br/>Waiting on Electrum Server...")
        else:
            explorer_status = Markup("Bitcoin Explorer<br/><br/>Requires Electrum Server")

        # Find VPN status
        if is_vpn_enabled():
            vpn_status_color = get_service_status_color("vpn")
            status_code = get_service_status_code("vpn")
            if status_code != 0:
                vpn_status = "Unknown"
            else:
                if os.path.isfile("/home/pivpn/ovpns/mynode_vpn.ovpn"):
                     vpn_status = "Running"
                else:
                    vpn_status = "Setting up..."

        # Find whirlpool status
        whirlpool_status, whirlpool_status_color, whirlpool_initialized = get_whirlpool_status()

        # Find dojo status
        dojo_status, dojo_status_color, dojo_initialized = get_dojo_status()
        if is_installing_docker_images():
            dojo_status_color = "yellow"
            dojo_status = "Installing..."

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
            "tor_status_color": tor_status_color,
            "is_installing_docker_images": is_installing_docker_images(),
            "electrs_status_color": electrs_status_color,
            "electrs_status": Markup(electrs_status),
            "electrs_enabled": is_electrs_enabled(),
            "rtl_status_color": rtl_status_color,
            "rtl_status": rtl_status,
            "lndhub_status_color": lndhub_status_color,
            "lndhub_enabled": is_lndhub_enabled(),
            "explorer_ready": explorer_ready,
            "explorer_status_color": explorer_status_color,
            "explorer_status": explorer_status,
            "btcrpcexplorer_ready": btcrpcexplorer_ready,
            "btcrpcexplorer_status_color": btcrpcexplorer_status_color,
            "btcrpcexplorer_status": btcrpcexplorer_status,
            "btcrpcexplorer_enabled": is_btcrpcexplorer_enabled(),
            "mempoolspace_status_color": mempoolspace_status_color,
            "mempoolspace_status": mempoolspace_status,
            "mempoolspace_enabled": is_mempoolspace_enabled(),
            "btcpayserver_enabled": is_btcpayserver_enabled(),
            "btcpayserver_status_color": btcpayserver_status_color,
            "btcpayserver_status": btcpayserver_status,
            "lndconnect_status_color": lndconnect_status_color,
            "vpn_status_color": vpn_status_color,
            "vpn_status": vpn_status,
            "vpn_enabled": is_vpn_enabled(),
            "whirlpool_status": whirlpool_status,
            "whirlpool_status_color": whirlpool_status_color,
            "whirlpool_enabled": is_whirlpool_enabled(),
            "whirlpool_initialized": whirlpool_initialized,
            "dojo_status": dojo_status,
            "dojo_status_color": dojo_status_color,
            "dojo_enabled": is_dojo_enabled(),
            "dojo_initialized": dojo_initialized,
            "product_key_skipped": pk_skipped,
            "product_key_error": pk_error,
            "fsck_error": has_fsck_error(),
            "fsck_results": get_fsck_results(),
            "sd_rw_error": has_sd_rw_error(),
            "drive_usage": get_drive_usage(),
            "cpu_usage": get_cpu_usage(),
            "ram_usage": get_ram_usage(),
            "swap_usage": get_swap_usage(),
            "device_temp": get_device_temp(),
            "upgrade_available": upgrade_available,
            "has_changed_password": has_changed_password(),
            "ui_settings": read_ui_settings()
        }
        return render_template('main.html', **templateData)
    else:
        templateData = {
            "title": "myNode Error",
            "header_text": "Error",
            "subheader_text": "Unknown State ("+status+"). Please restart your myNode.",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)

@app.route("/product-key", methods=['GET','POST'])
def page_product_key():
    check_logged_in()

    # If get, just display page
    if request.method == 'GET':
        templateData = {
            "title": "myNode Product Key",
            "header_text": "Product Key",
            "ui_settings": read_ui_settings()
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
    check_logged_in()
    if is_lndhub_enabled():
        disable_lndhub()
    else:
        enable_lndhub()
    return redirect("/")

@app.route("/toggle-electrs")
def page_toggle_electrs():
    check_logged_in()
    if is_electrs_enabled():
        disable_electrs()
    else:
        enable_electrs()
    return redirect("/")

@app.route("/toggle-btcrpcexplorer")
def page_toggle_btcrpcexplorer():
    check_logged_in()
    if is_btcrpcexplorer_enabled():
        disable_btcrpcexplorer()
    else:
        enable_btcrpcexplorer()
    return redirect("/")

@app.route("/toggle-mempoolspace")
def page_toggle_mempoolspace():
    check_logged_in()
    if is_mempoolspace_enabled():
        disable_mempoolspace()
    else:
        enable_mempoolspace()
    return redirect("/")

@app.route("/toggle-btcpayserver")
def page_toggle_btcpayserver():
    check_logged_in()
    if is_btcpayserver_enabled():
        disable_btcpayserver()
    else:
        enable_btcpayserver()
    return redirect("/")

@app.route("/toggle-vpn")
def page_toggle_vpn():
    check_logged_in()
    if is_vpn_enabled():
        disable_vpn()
    else:
        enable_vpn()
    return redirect("/")

@app.route("/toggle-whirlpool")
def page_toggle_whirlpool():
    check_logged_in()
    if is_whirlpool_enabled():
        disable_whirlpool()
    else:
        enable_whirlpool()
    return redirect("/")

@app.route("/toggle-dojo")
def page_toggle_dojo():
    check_logged_in()
    if is_dojo_enabled():
        disable_dojo()
    else:
        enable_dojo()
    return redirect("/")

@app.route("/login", methods=["GET","POST"])
def page_login():
    templateData = {
        "has_changed_password": has_changed_password(),
        "ui_settings": read_ui_settings()
    }
    if request.method == 'GET':
        return render_template('login.html', **templateData)

    pw = request.form.get('password')
    if login(pw):
        return redirect("/")
    else:
        flash("Invalid Password", category="error")
        return redirect("/login")

@app.route("/logout")
def page_logout():
    logout()
    return redirect("/")

@app.route("/about")
def page_about():
    check_logged_in()
    templateData = {"ui_settings": read_ui_settings()}
    return render_template('about.html', **templateData)

@app.route("/help")
def page_help():
    check_logged_in()
    templateData = {"ui_settings": read_ui_settings()}
    return render_template('help.html', **templateData)

## Error handlers
@app.errorhandler(404)
def not_found_error(error):
    templateData = {
        "title": "myNode 404",
        "header_text": "Page not found",
        "subheader_text": "Click on the myNode logo to reach the home page",
        "ui_settings": read_ui_settings()
    }
    return render_template('state.html', **templateData), 404

@app.errorhandler(500)
def internal_error(error):
    templateData = {
        "title": "myNode 500",
        "header_text": "Internal server error",
        "subheader_text": "If you were manually upgrading myNode, redo it.",
        "ui_settings": read_ui_settings()
    }
    return render_template('state.html', **templateData), 500

# Disable browser caching
@app.after_request
def set_response_headers(response):
    #response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    #response.headers['Pragma'] = 'no-cache'
    #response.headers['Expires'] = '0'
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
    public_ip_thread = BackgroundThread(find_public_ip, 60*60*3) # 3-hour repeat
    public_ip_thread.start()
    checkin_thread = BackgroundThread(check_in, 60*60*24) # Per-day checkin
    checkin_thread.start()

    my_logger = logging.getLogger('FlaskLogger')
    my_logger.setLevel(logging.DEBUG)
    handler = logging.handlers.RotatingFileHandler(filename='/var/log/flask', maxBytes=2000000, backupCount=2)
    my_logger.addHandler(handler)
    app.logger.addHandler(my_logger)

    app.register_error_handler(LoginError, handle_login_exception)

    app.secret_key = 'NoZlPx7t15foPfKpivbVrTrTy2bTQ99chJoz3LFmf5BFsh3Nz4ud0mMpGjtB4bhP'
    app.permanent_session_lifetime = timedelta(days=90)

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
