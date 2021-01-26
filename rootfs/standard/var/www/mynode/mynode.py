
from config import *
from flask import Flask, render_template, Markup, send_from_directory, redirect, request, url_for
from user_management import *
from api import mynode_api
from bitcoind import mynode_bitcoind
from whirlpool import mynode_whirlpool, get_whirlpool_status
from dojo import mynode_dojo, get_dojo_status
from caravan import mynode_caravan
from manage_apps import mynode_manage_apps
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
from device_warnings import *
from systemctl_info import *
import pam
import re
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

# Proxy class to redirect to HTTP or HTTPS depending on connection
class ReverseProxied(object):
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        scheme = environ.get('HTTP_X_FORWARDED_PROTO')
        if scheme:
            environ['wsgi.url_scheme'] = scheme
        return self.app(environ, start_response)


app = Flask(__name__)
app.config['DEBUG'] = False
app.config['TEMPLATES_AUTO_RELOAD'] = True
app.config['MAX_CONTENT_LENGTH'] = 32 * 1024 * 1024     # 32 MB upload file max
app.config['UPLOAD_FOLDER'] = "/tmp/flask_uploads"
app.config["SESSION_COOKIE_NAME"] = "mynode_session_id"
app.secret_key = get_flask_secret_key()
app.permanent_session_lifetime = timedelta(days=90)
app.register_error_handler(LoginError, handle_login_exception)

app.wsgi_app = ReverseProxied(app.wsgi_app)

my_logger = logging.getLogger('FlaskLogger')
my_logger.setLevel(logging.DEBUG)
handler = logging.handlers.RotatingFileHandler(filename='/var/log/flask', maxBytes=2000000, backupCount=2)
my_logger.addHandler(handler)
app.logger.addHandler(my_logger)
app.logger.setLevel(logging.INFO)

app.register_blueprint(mynode_bitcoind)
app.register_blueprint(mynode_lnd)
app.register_blueprint(mynode_api)
app.register_blueprint(mynode_whirlpool)
app.register_blueprint(mynode_dojo)
app.register_blueprint(mynode_caravan)
app.register_blueprint(mynode_manage_apps)
app.register_blueprint(mynode_tor)
app.register_blueprint(mynode_electrum_server)
app.register_blueprint(mynode_vpn)
app.register_blueprint(mynode_settings)

### Definitions
MYNODE_DIR =    "/mnt/hdd/mynode"
BITCOIN_DIR =   "/mnt/hdd/mynode/bitcoin"
LN_DIR =        "/mnt/hdd/mynode/lnd"

### Global Variables
need_to_stop = False
threads = []

# Exception to throw on exit
class ServiceExit(Exception):
    pass

# Function to run on exit
def on_shutdown(signum, frame):
    app.logger.info('Caught signal %d' % signum)
    raise ServiceExit


### Flask Page Processing
@app.route("/")
def index():
    check_logged_in()
    status = get_mynode_status()

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

    if status == STATE_UNKNOWN:
        templateData = {
            "title": "myNode Error",
            "header_text": "Status Unknown",
            "subheader_text": "An error has occurred. You may want to reboot the device.",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_ROOTFS_READ_ONLY:
        templateData = {
            "title": "myNode Error",
            "header_text": "SD Card Error",
            "subheader_text": "The root filesystem is read only. Your SD card may be corrupt.",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_HDD_READ_ONLY:
        templateData = {
            "title": "myNode Error",
            "header_text": "Drive Error",
            "subheader_text": "The external drive filesystem is read only. Try rebooting the device.",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif is_warning_present():
        warning = get_current_warning()
        templateData = {
            "title": "myNode Warning",
            "header_text": "Warning",
            "subheader_text": get_warning_header(warning),
            "description_text": get_warning_description(warning),
            "warning_name": warning,
            "ui_settings": read_ui_settings()
        }
        return render_template('warning.html', **templateData)
    elif status == STATE_DRIVE_MISSING:
        # Drive may be getting repaired
        if is_drive_being_repaired():
            templateData = {
                "title": "myNode Repairing Drive",
                "header_text": "Repairing Drive",
                "subheader_text": Markup("Drive is being checked and repaired...<br/><br/>This may take several hours."),
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
    elif status == STATE_GEN_DHPARAM:
        templateData = {
            "title": "myNode Generating Data",
            "header_text": "Generating Data",
            "subheader_text": "This may take 15-20 minutes...",
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
    elif status == STATE_UPGRADING:
        templateData = {
            "title": "myNode Upgrading",
            "header_text": "Upgrading...",
            "subheader_text": "This may take a while...",
            "refresh_rate": 120,
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_SHUTTING_DOWN or is_shutting_down():
        templateData = {
            "title": "myNode Reboot",
            "header_text": "Restarting",
            "subheader_text": "This will take several minutes...",
            "refresh_rate": 120,
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
        electrs_active = is_electrs_active()
        bitcoind_status = "Inactive"
        lnd_status = "Inactive"
        electrs_status = ""
        lndconnect_status_color = "gray"
        btcpayserver_status_color = "gray"
        mempoolspace_status_color = "gray"
        vpn_status_color = "gray"
        vpn_status = ""
        current_block = 1234

        if not get_has_updated_btc_info() or uptime_in_seconds < 180:
            error_message = ""
            if bitcoind_status_code != 0 and uptime_in_seconds > 600:
                error_message = "Bitcoin has experienced an error. Please check the logs."
            message = "<div class='small_message'>{}</<div>".format( get_message(include_funny=True) )
            templateData = {
                "title": "myNode Status",
                "header_text": "Starting...",
                "subheader_text": Markup("Launching myNode Services{}".format(message)),
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
                "refresh_rate": 10,
                "ui_settings": read_ui_settings()
            }
            return render_template('state.html', **templateData)

        # Find tor status
        tor_status_color = get_service_status_color("tor@default")
        tor_status = "Private Connections"

        # Find bitcoind status
        bitcoin_info = get_bitcoin_blockchain_info()
        bitcoin_peers = get_bitcoin_peers()
        if bitcoind_status_code != 0:
            bitcoind_status_color = "red"
        else:
            bitcoind_status_color = "green"
            bitcoind_status = get_bitcoin_status()
            current_block = get_mynode_block_height()

        # Find lnd status
        lnd_status = get_lnd_status()
        lnd_status_color = get_lnd_status_color()

        # Find drive usage
        drive_usage = get_drive_usage()
        low_drive_space_error = False
        if int(re.sub("[^0-9]", "", drive_usage)) > 95:
            low_drive_space_error = True


        # Find lndhub status
        lndhub_status, lndhub_status_color = get_lndhub_status_and_color()

        # Find RTL status
        rtl_status, rtl_status_color = get_rtl_status_and_color()

        # Find LNbits status
        lnbits_status, lnbits_status_color = get_lnbits_status_and_color()

        # Find Thunderhub status
        thunderhub_status, thunderhub_status_color = get_thunderhub_status_and_color()

        # Find electrs status
        electrs_status, electrs_status_color = get_electrs_status_and_color()

        # Find btc-rpc-explorer status
        btcrpcexplorer_status, btcrpcexplorer_status_color, btcrpcexplorer_ready = get_btcrpcexplorer_status_and_color_and_ready()

        # Find mempool space status
        mempoolspace_status, mempoolspace_status_color = get_mempool_status_and_color()

        # Find btcpayserver status
        btcpayserver_status, btcpayserver_status_color = get_btcpayserver_status_and_color()

        # Find VPN status
        vpn_status, vpn_status_color = get_vpn_status_and_color()

        # Find whirlpool status
        whirlpool_status, whirlpool_status_color, whirlpool_initialized = get_whirlpool_status()

        # Find dojo status
        dojo_status, dojo_status_color, dojo_initialized = get_dojo_status()

        # Find caravan status
        caravan_status, caravan_status_color = get_caravan_status_and_color()

        # Find specter status
        specter_status, specter_status_color = get_specter_status_and_color()

        # Check for new version of software
        upgrade_available = False
        current = get_current_version()
        latest = get_latest_version()
        if current != "0.0" and latest != "0.0" and current != latest:
            upgrade_available = True

        # Refresh rate
        refresh_rate = 3600 * 24
        if bitcoind_status_color == "red" or lnd_status_color == "red":
            refresh_rate = 60
        elif bitcoind_status_color == "yellow" or lnd_status_color == "yellow":
            refresh_rate = 120

        templateData = {
            "title": "myNode Home",
            "refresh_rate": refresh_rate,
            "config": CONFIG,
            "bitcoind_status_color": bitcoind_status_color,
            "bitcoind_status": Markup(bitcoind_status),
            "current_block": current_block,
            "bitcoin_peer_count": get_bitcoin_peer_count(),
            "bitcoin_difficulty": get_bitcoin_difficulty(),
            "bitcoin_mempool_size": get_bitcoin_mempool_size(),
            "bitcoin_version": get_bitcoin_version(),
            "lnd_status_color": lnd_status_color,
            "lnd_status": Markup(lnd_status),
            "lnd_ready": lnd_ready,
            "lnd_peer_count": get_lightning_peer_count(),
            "lnd_channel_count": get_lightning_channel_count(),
            "lnd_balance_info": get_lightning_balance_info(),
            "lnd_version": get_lnd_version(),
            "tor_status_color": tor_status_color,
            "tor_status": tor_status,
            "is_installing_docker_images": is_installing_docker_images(),
            "is_device_from_reseller": is_device_from_reseller(),
            "electrs_status_color": electrs_status_color,
            "electrs_status": Markup(electrs_status),
            "electrs_enabled": is_electrs_enabled(),
            "electrs_active": electrs_active,
            "rtl_status_color": rtl_status_color,
            "rtl_status": rtl_status,
            "rtl_enabled": is_rtl_enabled(),
            "lnbits_status_color": lnbits_status_color,
            "lnbits_status": lnbits_status,
            "lnbits_enabled": is_lnbits_enabled(),
            "thunderhub_status_color": thunderhub_status_color,
            "thunderhub_status": thunderhub_status,
            "thunderhub_enabled": is_thunderhub_enabled(),
            "lndhub_status_color": lndhub_status_color,
            "lndhub_status": lndhub_status,
            "lndhub_enabled": is_lndhub_enabled(),
            "btcrpcexplorer_ready": btcrpcexplorer_ready,
            "btcrpcexplorer_status_color": btcrpcexplorer_status_color,
            "btcrpcexplorer_status": btcrpcexplorer_status,
            "btcrpcexplorer_enabled": is_btcrpcexplorer_enabled(),
            "btcrpcexplorer_sso_token": get_btcrpcexplorer_sso_token(),
            "caravan_status_color": caravan_status_color,
            "caravan_status": caravan_status,
            "caravan_enabled": is_caravan_enabled(),
            "specter_status_color": specter_status_color,
            "specter_status": specter_status,
            "specter_enabled": is_specter_enabled(),
            "mempoolspace_status_color": mempoolspace_status_color,
            "mempoolspace_status": mempoolspace_status,
            "mempoolspace_enabled": is_mempoolspace_enabled(),
            "btcpayserver_enabled": is_btcpayserver_enabled(),
            "btcpayserver_status_color": btcpayserver_status_color,
            "btcpayserver_status": btcpayserver_status,
            "vpn_status_color": vpn_status_color,
            "vpn_status": vpn_status,
            "vpn_enabled": is_vpn_enabled(),
            "whirlpool_status": whirlpool_status,
            "whirlpool_status_color": whirlpool_status_color,
            "whirlpool_enabled": is_whirlpool_enabled(),
            "whirlpool_initialized": whirlpool_initialized,
            "is_dojo_installed": is_dojo_installed(),
            "dojo_status": dojo_status,
            "dojo_status_color": dojo_status_color,
            "dojo_enabled": is_dojo_enabled(),
            "dojo_initialized": dojo_initialized,
            "product_key_skipped": pk_skipped,
            "product_key_error": pk_error,
            "fsck_error": has_fsck_error(),
            "fsck_results": get_fsck_results(),
            "sd_rw_error": has_sd_rw_error(),
            "drive_usage": drive_usage,
            "low_drive_space_error": low_drive_space_error,
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

@app.route("/ignore-warning")
def page_ignore_warning():
    check_logged_in()
    if request.method == 'GET':
        warning = request.args.get('warning')
        skip_warning(warning)
    return redirect("/")

@app.route("/toggle-lndhub")
def page_toggle_lndhub():
    check_logged_in()
    if is_lndhub_enabled():
        disable_lndhub()
    else:
        enable_lndhub()
    return redirect("/")

@app.route("/toggle-thunderhub")
def page_toggle_thunderhub():
    check_logged_in()
    if is_thunderhub_enabled():
        disable_thunderhub()
    else:
        enable_thunderhub()
    return redirect("/")

@app.route("/toggle-electrs")
def page_toggle_electrs():
    check_logged_in()
    if is_electrs_enabled():
        disable_electrs()
    else:
        enable_electrs()
    return redirect("/")

@app.route("/toggle-rtl")
def page_toggle_rtl():
    check_logged_in()
    if is_rtl_enabled():
        disable_rtl()
    else:
        enable_rtl()
    return redirect("/")

@app.route("/toggle-lnbits")
def page_toggle_lnbits():
    check_logged_in()
    if is_lnbits_enabled():
        disable_lnbits()
    else:
        enable_lnbits()
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

@app.route("/toggle-caravan")
def page_toggle_caravan():
    check_logged_in()
    if is_caravan_enabled():
        disable_caravan()
    else:
        enable_caravan()
    return redirect("/")

@app.route("/toggle-specter")
def page_toggle_specter():
    check_logged_in()
    if is_specter_enabled():
        disable_specter()
    else:
        enable_specter()
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

@app.route("/toggle-dojo-install")
def page_toggle_dojo_install():
    check_logged_in()

    # In case of refresh, mark toggle was started
    check_and_mark_reboot_action("toggle_dojo_install")

    if is_dojo_installed():
        # Mark app as not installed
        uninstall_dojo()        

        # Re-install app (this will uninstall and not re-install after reboot since install file is missing)
        t = Timer(1.0, reinstall_app, ["dojo"])
        t.start()

        # Display wait page
        templateData = {
            "title": "myNode Uninstall",
            "header_text": "Uninstalling",
            "subheader_text": "This may take a while...",
            "ui_settings": read_ui_settings()
        }
        return render_template('reboot.html', **templateData)
    else:
        # Mark Dojo for install
        install_dojo()

        # Re-install app
        t = Timer(1.0, reboot_device)
        t.start()

        # Display wait page
        templateData = {
            "title": "myNode Install",
            "header_text": "Installing",
            "subheader_text": "This may take a while...",
            "ui_settings": read_ui_settings()
        }
        return render_template('reboot.html', **templateData)

    return redirect("/")

@app.route("/clear-fsck-error")
def page_clear_fsck_error():
    check_logged_in()
    clear_fsck_error()
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
        flash(get_login_error_message(), category="error")
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

# Check for forced HTTPS
@app.before_request
def before_request():
    if is_https_forced():
        scheme = request.headers.get('X-Forwarded-Proto')
        if scheme and scheme == 'http' and request.url.startswith('http://'):
            url = request.url.replace('http://', 'https://', 1)
            code = 302
            app.logger.info("Redirecting to HTTPS ({})".format(url))
            return redirect(url, code=code)

# Disable browser caching
@app.after_request
def set_response_headers(response):
    # Prevents 301 from saving forever
    response.headers['Cache-Control'] = 'no-store'

    # No Caching
    #response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    #response.headers['Pragma'] = 'no-cache'
    #response.headers['Expires'] = '0'
    return response

@app.before_first_request
def before_first_request():
    app.logger.info("BEFORE_FIRST_REQUEST START")

    # Need to do anything here?

    app.logger.info("BEFORE_FIRST_REQUEST END")
    

def start_threads():
    global threads
    app.logger.info("STARTING THREADS")

    # Start threads
    btc_thread1 = BackgroundThread(update_bitcoin_main_info_thread, 10)
    btc_thread1.start()
    threads.append(btc_thread1)
    btc_thread2 = BackgroundThread(update_bitcoin_other_info_thread, 30)
    btc_thread2.start()
    threads.append(btc_thread2)
    electrs_info_thread = BackgroundThread(update_electrs_info_thread, 60)
    electrs_info_thread.start()
    threads.append(electrs_info_thread)
    lnd_thread = BackgroundThread(update_lnd_info_thread, 60)
    lnd_thread.start()
    threads.append(lnd_thread)
    drive_thread = BackgroundThread(update_device_info, 60)
    drive_thread.start()
    threads.append(drive_thread)
    public_ip_thread = BackgroundThread(find_public_ip, 60*60*12) # 12-hour repeat
    public_ip_thread.start()
    threads.append(public_ip_thread)

    app.logger.info("STARTED {} THREADS".format(len(threads)))

def stop_threads():
    global threads

    # Stop threads
    app.logger.info("STOPPING {} THREADS".format(len(threads)))
    for t in threads:
        app.logger.info("Killing {}".format(t.pid))
        os.kill(t.pid, signal.SIGKILL)

def stop_app():
    app.logger.info("STOP_APP START")

    stop_threads()

    # Shutdown Flask (if used)
    func = request.environ.get('werkzeug.server.shutdown')
    if func is None:
        raise RuntimeError('Not running with the Werkzeug Server')
    else:
        func()

    app.logger.info("STOP_APP END")

if __name__ == "__main__":

    # Handle signals
    signal.signal(signal.SIGTERM, on_shutdown)
    signal.signal(signal.SIGINT, on_shutdown)

    # Setup and start threads
    start_threads()

    try:
        app.run(host='0.0.0.0', port=80)
    except ServiceExit:
        # Stop background threads
        stop_app()

    app.logger.info("Service www exiting...")
