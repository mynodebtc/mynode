
from config import *
from flask import Flask, render_template, Markup, redirect, request, url_for
from user_management import *
from api import mynode_api
from bitcoin import mynode_bitcoin
from whirlpool import mynode_whirlpool
from dojo import mynode_dojo
from joinmarket import mynode_joinmarket
from caravan import mynode_caravan
from sphinxrelay import mynode_sphinxrelay
from pyblock import mynode_pyblock
from bos import mynode_bos
from wardenterminal import mynode_wardenterminal
from lndmanage import mynode_lndmanage
from generic_app import mynode_generic_app
from manage_apps import mynode_manage_apps
from marketplace import mynode_marketplace
from usb_extras import mynode_usb_extras
from premium_plus import mynode_premium_plus
from tor import mynode_tor
from vpn import mynode_vpn
from electrum_server import *
from lnd import mynode_lnd, lnd_wallet_exists, is_lnd_logged_in, lnd_get, get_lnd_status
from settings import *
from pprint import pprint
from background_thread import BackgroundThread
from prometheus_client.parser import text_string_to_metric_families
from bitcoin_info import *
from lightning_info import *
from messages import get_message
from thread_functions import *
from datetime import timedelta
from device_info import *
from drive_info import *
from device_warnings import *
from systemctl_info import *
from application_info import *
from price_info import *
from utilities import *
import importlib
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
app.config['SESSION_PERMANENT'] = True
app.config["SESSION_COOKIE_NAME"] = "mynode_session_id"
app.secret_key = get_flask_secret_key()
timeout_days, timeout_hours = get_flask_session_timeout()
app.permanent_session_lifetime = timedelta(days=timeout_days, hours=timeout_hours)
app.register_error_handler(LoginError, handle_login_exception)

app.wsgi_app = ReverseProxied(app.wsgi_app)

my_logger = logging.getLogger('FlaskLogger')
my_logger.setLevel(logging.DEBUG)
handler = logging.handlers.RotatingFileHandler(filename='/var/log/flask', maxBytes=2000000, backupCount=2)
my_logger.addHandler(handler)
app.logger.addHandler(my_logger)
app.logger.setLevel(logging.INFO)

app.register_blueprint(mynode_bitcoin)
app.register_blueprint(mynode_lnd)
app.register_blueprint(mynode_api)
app.register_blueprint(mynode_whirlpool)
app.register_blueprint(mynode_dojo)
app.register_blueprint(mynode_joinmarket)
app.register_blueprint(mynode_caravan)
app.register_blueprint(mynode_sphinxrelay)
app.register_blueprint(mynode_pyblock)
app.register_blueprint(mynode_bos)
app.register_blueprint(mynode_wardenterminal)
app.register_blueprint(mynode_lndmanage)
app.register_blueprint(mynode_manage_apps)
app.register_blueprint(mynode_marketplace)
app.register_blueprint(mynode_generic_app)
app.register_blueprint(mynode_tor)
app.register_blueprint(mynode_premium_plus)
app.register_blueprint(mynode_electrum_server)
app.register_blueprint(mynode_vpn)
app.register_blueprint(mynode_usb_extras)
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
    product_key_skipped = skipped_product_key()
    product_key_error = not is_valid_product_key()

    # Show uploader page if we are marked as an uploader
    if is_uploader():
        status=""
        try:
            status = to_string(subprocess.check_output(["mynode-get-quicksync-status"]))
        except:
            status = "Waiting on quicksync to start..."

        status = status.decode("utf8")
        status = Markup("<div style='text-align: left; font-size: 12px; width: 800px;'><pre>"+status+"</pre></div>")
        templateData = {
            "title": "Uploader",
            "header_text": "Uploader Device",
            "quicksync_status": status,
            "ui_settings": read_ui_settings()
        }
        return render_template('uploader.html', **templateData)

    if status == STATE_UNKNOWN:
        templateData = {
            "title": "Error",
            "header_text": "Status Unknown",
            "subheader_text": "An error has occurred. You may want to reboot the device.",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_ROOTFS_READ_ONLY:
        templateData = {
            "title": "Error",
            "header_text": "OS Drive Error",
            "subheader_text": "The root filesystem is read only. Your SD card or USB thumdrive may be corrupt.",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_HDD_READ_ONLY:
        templateData = {
            "title": "Error",
            "header_text": "Drive Error",
            "subheader_text": "The external drive filesystem is read only. Try rebooting the device.",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif is_warning_present():
        warning = get_current_warning()
        templateData = {
            "title": "Warning",
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
                "title": "Repairing Drive",
                "header_text": "Repairing Drive",
                "subheader_text": Markup("Drive is being checked and repaired...<br/><br/>This may take several hours."),
                "ui_settings": read_ui_settings()
            }
            return render_template('state.html', **templateData)

        templateData = {
            "title": "Looking for Drive",
            "header_text": "Looking for Drive",
            "subheader_text": "Please attach a drive to your MyNode",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_DRIVE_CONFIRM_FORMAT:
        if request.args.get('format'):
            touch("/tmp/format_ok")
            os.system("rm -f /home/bitcoin/.mynode/force_format_prompt")
            time.sleep(1)
            return redirect("/")

        templateData = {
            "title": "Confirm Drive Format",
            "ui_settings": read_ui_settings()
        }
        return render_template('confirm_drive_format.html', **templateData)
    elif status == STATE_DRIVE_FORMATTING:
        templateData = {
            "title": "Drive Formatting",
            "header_text": "Drive Formatting",
            "subheader_text": "MyNode is preparing the drive for use...",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_DRIVE_MOUNTED:
        templateData = {
            "title": "Starting",
            "header_text": "Starting...",
            "subheader_text": "Drive Mounted",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_CHOOSE_NETWORK:
        templateData = {
            "title": "Choose Network",
            "ui_settings": read_ui_settings()
        }
        return render_template('choose_network.html', **templateData)
    elif status == STATE_CHOOSE_IMPLEMENTATION:
        templateData = {
            "title": "Choose Bitcoin Implementation",
            "ui_settings": read_ui_settings()
        }
        return render_template('choose_bitcoin_implementation.html', **templateData)
    elif status == STATE_DOCKER_RESET:
        templateData = {
            "title": "MyNode",
            "header_text": "Resetting Docker Data",
            "subheader_text": "This will take several minutes...",
            "ui_settings": read_ui_settings()
        }
        return render_template('reboot.html', **templateData)
    elif status == STATE_DRIVE_FULL:
        message  = "Your drive is full!<br/><br/>"
        message += "<p style='font-size: 16px; width: 800px; margin: auto;'>"
        message += "To prevent corrupting any data, your device has stopped running most apps until more free space is available. "
        message += "Please free up some space or attach a larger drive.<br/><br/>"
        message += "If enabled, disabling <a href='/settings#quicksync'>QuickSync</a> can save a large amount of space.<br/><br/>"
        message += "To move to larger drive, try the <a href='/settings#clone_tool'>Clone Tool</a>."
        message += "</p>"
        templateData = {
            "title": "Drive Full",
            "header_text": "Drive Full",
            "subheader_text": Markup(message),
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_DRIVE_CLONE:
        clone_state = get_clone_state()
        log_message("CLONE_STATE")
        log_message(clone_state)
        if clone_state == CLONE_STATE_DETECTING:
            templateData = {
                "title": "Clone Tool",
                "header_text": "Cloning Tool",
                "subheader_text": Markup("Detecting Drives..."),
                "ui_settings": read_ui_settings(),
                "refresh_rate": 10
            }
            return render_template('state.html', **templateData)
        elif clone_state == CLONE_STATE_ERROR:
            # Error is being cleared
            if request.args.get('clone_clear_error'):
                os.system("rm /tmp/.clone_error")
                time.sleep(3)
                return redirect("/")

            # Show Error
            error = get_clone_error()
            msg  = ""
            msg += "Clone Error<br/></br>"
            msg += error
            msg += "<br/><br/><br/>"
            msg += "<a class='ui-button ui-widget ui-corner-all mynode_button_small' style='width: 120px;' href='/?clone_clear_error=1'>Try Again</a>"
            msg += "<br/><br/>"
            msg += "<a class='ui-button ui-widget ui-corner-all mynode_button_small' style='width: 120px;' href='/settings/reboot-device'>Exit Clone Tool</a>"
            templateData = {
                "title": "Clone Tool",
                "header_text": "Cloning Tool",
                "subheader_text": Markup(msg),
                "ui_settings": read_ui_settings(),
                "refresh_rate": 10
            }
            return render_template('state.html', **templateData)
        elif clone_state == CLONE_STATE_NEED_CONFIRM:
            # Clone was confirmed
            if request.args.get('clone_confirm'):
                touch("/tmp/.clone_confirm")
                time.sleep(3)
                return redirect("/")
            if request.args.get('clone_rescan'):
                touch("/tmp/.clone_rescan")
                time.sleep(3)
                return redirect("/")

            source_drive = get_clone_source_drive()
            target_drive = get_clone_target_drive()
            target_drive_has_mynode = get_clone_target_drive_has_mynode()
            source_drive_info = get_drive_info(source_drive)
            target_drive_info = get_drive_info(target_drive)
            templateData = {
                "title": "Clone Tool",
                "header_text": "Cloning Tool",
                "target_drive_has_mynode": target_drive_has_mynode,
                "source_drive_info": source_drive_info,
                "target_drive_info": target_drive_info,
                "ui_settings": read_ui_settings(),
            }
            return render_template('clone_confirm.html', **templateData)
        elif clone_state == CLONE_STATE_IN_PROGRESS:
            progress = get_clone_progress()
            templateData = {
                "title": "Clone Tool",
                "header_text": "Cloning Tool",
                "subheader_text": Markup("Cloning...<br/><br/>" + progress),
                "ui_settings": read_ui_settings(),
                "refresh_rate": 5
            }
            return render_template('state.html', **templateData)
        elif clone_state == CLONE_STATE_COMPLETE:
            templateData = {
                "title": "Clone Tool",
                "header_text": "Cloning Tool",
                "subheader_text": Markup("Clone Complete!"),
                "ui_settings": read_ui_settings(),
            }
            return render_template('clone_complete.html', **templateData)
        else:
            templateData = {
                "title": "Clone Tool",
                "header_text": "Cloning Tool",
                "subheader_text": "Unknown Clone State: " + clone_state,
                "ui_settings": read_ui_settings()
            }
            return render_template('state.html', **templateData)
    elif status == STATE_GEN_DHPARAM:
        templateData = {
            "title": "Generating Data",
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
            current = to_string(subprocess.check_output(["du","-m","--max-depth=0","/mnt/hdd/mynode/bitcoin/"]).split()[0])
            total = to_string(subprocess.check_output(["du","-m","--max-depth=0","/mnt/hdd/mynode/quicksync/"]).split()[0])
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
            "title": "QuickSync",
            "header_text": "QuickSync",
            "subheader_text": subheader_msg,
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_QUICKSYNC_RESET:
        templateData = {
            "title": "QuickSync",
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
            "title": "QuickSync",
            "header_text": "QuickSync",
            "subheader_text": subheader,
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_UPGRADING:
        templateData = {
            "title": "Upgrading",
            "header_text": "Upgrading...",
            "subheader_text": "This may take a while...",
            "refresh_rate": 120,
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)
    elif status == STATE_SHUTTING_DOWN or is_shutting_down():
        return redirect("/rebooting")
    elif status == STATE_STABLE:
        bitcoin_status_code = get_service_status_code("bitcoin")
        bitcoin_status_color = "red"
        lnd_status_color = "red"
        lnd_ready = is_lnd_ready()
        electrs_active = is_electrs_active()
        bitcoin_status = "Inactive"
        lnd_status = "Inactive"
        current_block = 1234

        if not get_has_updated_btc_info() or uptime_in_seconds < 180:
            error_message = ""
            if bitcoin_status_code != 0 and uptime_in_seconds > 600:
                error_message = "Bitcoin has experienced an error. Please check the Bitcoin log on the status page."
            message = "<div class='small_message'>{}</<div>".format( get_message(include_funny=True) )
            templateData = {
                "title": "Starting",
                "header_text": "Starting...",
                "subheader_text": Markup("Launching MyNode Services{}".format(message)),
                "error_message": Markup(error_message + "<br/><br/>"),
                "ui_settings": read_ui_settings()
            }
            return render_template('state.html', **templateData)

        # if is_installing_docker_images():
        #     message = "<div class='small_message'>{}</<div>".format( get_message(include_funny=True) )
        #     templateData = {
        #         "title": "Status",
        #         "header_text": "Starting...",
        #         "subheader_text": Markup("Building Docker Images...{}".format(message)),
        #         "ui_settings": read_ui_settings()
        #     }
        #     return render_template('state.html', **templateData)

        # Display sync info if not synced
        if not is_bitcoin_synced():
            subheader = Markup("Syncing...")
            if bitcoin_block_height == None:
                bitcoin_block_height = 0
            if mynode_block_height == None:
                mynode_block_height = 0
            templateData = {
                "title": "Sync",
                "header_text": "Bitcoin Blockchain",
                "bitcoin_block_height": bitcoin_block_height,
                "mynode_block_height": mynode_block_height,
                "progress": get_bitcoin_sync_progress(),
                "message": get_message(include_funny=True),
                "ui_settings": read_ui_settings()
            }
            return render_template('syncing.html', **templateData)

        # Find bitcoid status
        if bitcoin_status_code != 0:
            bitcoin_status_color = "red"
        else:
            bitcoin_status_color = "green"
            bitcoin_status = get_bitcoin_status()
            current_block = get_mynode_block_height()

        # Find lnd status
        lnd_status = get_lnd_status()
        lnd_status_color = get_lnd_status_color()

        # Find drive / SD card usage
        os_drive_usage = get_os_drive_usage()
        data_drive_usage = get_data_drive_usage()
        low_drive_space_error = False
        low_os_drive_space_error = False
        if int(re.sub("[^0-9]", "", data_drive_usage)) >= 95:
            low_drive_space_error = True
        if int(re.sub("[^0-9]", "", os_drive_usage)) >= 95:
            low_os_drive_space_error = True

        # Check for new version of software
        upgrade_available = False
        current = get_current_version()
        latest = get_latest_version()
        if current != "0.0" and latest != "0.0" and current != latest:
            upgrade_available = True

        # Refresh rate
        refresh_rate = 3600 * 24
        if bitcoin_status_color == "red" or lnd_status_color == "red":
            refresh_rate = 60
        elif bitcoin_status_color == "yellow" or lnd_status_color == "yellow":
            refresh_rate = 120

        templateData = {
            "title": "Home",
            "refresh_rate": refresh_rate,
            "config": CONFIG,
            "apps": get_all_applications(order_by="homepage"),
            "bitcoin_status_color": bitcoin_status_color,
            "bitcoin_status": Markup(bitcoin_status),
            "current_block": current_block,
            "bitcoin_peer_count": get_bitcoin_peer_count(),
            "bitcoin_difficulty": get_bitcoin_difficulty(),
            "bitcoin_mempool_size": get_bitcoin_mempool_info()["display_bytes"],
            "bitcoin_version": get_bitcoin_version(),
            "lnd_status_color": lnd_status_color,
            "lnd_status": Markup(lnd_status),
            "lnd_ready": lnd_ready,
            "lnd_peer_count": get_lightning_peer_count(),
            "lnd_channel_count": get_lightning_channel_count(),
            "lnd_balance_info": get_lightning_balance_info(),
            "lnd_wallet_exists": lnd_wallet_exists(),
            "lnd_version": get_lnd_version(),
            "lnd_deposit_address": get_lnd_deposit_address(),
            "lnd_transactions": get_lightning_transactions(),
            "lnd_payments_and_invoices": get_lightning_payments_and_invoices(),
            "lnd_tx_display_limit": 6,
            "lnd_channels": get_lightning_channels(),
            "electrs_active": electrs_active,
            "btcpayserver_onion": get_onion_url_btcpay(),
            "lndhub_onion": get_onion_url_lndhub(),
            "lnbits_onion": get_onion_url_lnbits(),
            "is_testnet_enabled": is_testnet_enabled(),
            "is_installing_docker_images": is_installing_docker_images(),
            "is_device_from_reseller": is_device_from_reseller(),
            "is_expiration_warning_dismissed": is_expiration_warning_dismissed(),
            "check_in_data": get_check_in_data(),
            "product_key_skipped": product_key_skipped,
            "product_key_error": product_key_error,
            "premium_plus_has_access_token": has_premium_plus_token(),
            "premium_plus_is_connected": get_premium_plus_is_connected(),
            "fsck_error": has_fsck_error(),
            "fsck_results": get_fsck_results(),
            "sd_rw_error": has_sd_rw_error(),
            "data_drive_usage": data_drive_usage,
            "os_drive_usage": os_drive_usage,
            "low_drive_space_error": low_drive_space_error,
            "low_os_drive_space_error": low_os_drive_space_error,
            "usb_error": has_usb_error(),
            "show_32_bit_warning": show_32_bit_warning(),
            "is_quicksync_disabled": not is_quicksync_enabled(),
            "usb_extras": get_usb_extras(),
            "cpu_usage": get_cpu_usage(),
            "ram_usage": get_ram_usage(),
            "swap_usage": get_swap_usage(),
            "device_temp": get_device_temp(),
            "upgrade_available": upgrade_available,
            "hide_password_warning": settings_file_exists("hide_password_warning"),
            "has_changed_password": has_changed_password(),
            "ui_settings": read_ui_settings()
        }
        return render_template('main.html', **templateData)
    else:
        templateData = {
            "title": "Error",
            "header_text": "Error",
            "subheader_text": "Unknown State ("+status+"). Please restart your MyNode.",
            "ui_settings": read_ui_settings()
        }
        return render_template('state.html', **templateData)

@app.route("/product-key", methods=['GET','POST'])
def page_product_key():
    check_logged_in()

    # If get, just display page
    if request.method == 'GET':
        # Check if recheck was specified
        if request.args.get("recheck"):
            recheck_product_key()
            flash("Your key will be re-checked shortly...", category="message")
            return redirect("/")
        else:
            templateData = {
                "title": "Product Key",
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

            t = Timer(1.0, restart_check_in)
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

@app.route("/toggle-enabled")
def page_toggle_app():
    check_logged_in()

    return_page = "/"
    if request.args.get("return_page"):
        return_page = request.args.get("return_page")

    # Check application specified
    if not request.args.get("app"):
        flash("No application specified", category="error")
        return redirect(return_page)
    
    # Check application name is valid
    app_short_name = request.args.get("app")
    if not is_application_valid(app_short_name):
        flash("Application is invalid", category="error")
        return redirect(return_page)

    # Toggle enabled/disabled
    if is_service_enabled(app_short_name):
        disable_service(app_short_name)
    else:
        enable_service(app_short_name)
    return redirect(return_page)

@app.route("/clear-fsck-error")
def page_clear_fsck_error():
    check_logged_in()
    clear_fsck_error()
    return redirect("/")

@app.route("/clear-32-bit-warning")
def page_clear_32_bit_warning():
    check_logged_in()
    hide_32_bit_warning()
    return redirect("/")

@app.route("/dismiss-expiration-warning")
def page_dismiss_expiration_warning():
    check_logged_in()
    dismiss_expiration_warning()
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

@app.route("/rebooting")
def page_rebooting():
    check_logged_in()
    
    # Show that device is rebooting and use JS to refresh once back online
    templateData = {
        "title": "Rebooting",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

## Error handlers
@app.errorhandler(404)
def not_found_error(error):
    templateData = {
        "title": "404 Error",
        "header_text": "Page not found",
        "subheader_text": "Click on the MyNode logo to reach the home page",
        "ui_settings": read_ui_settings()
    }
    return render_template('state.html', **templateData), 404

@app.errorhandler(500)
def internal_error(error):
    templateData = {
        "title": "500 Error",
        "header_text": "Internal server error",
        "subheader_text": "If you were manually upgrading MyNode, please try again.",
        "ui_settings": read_ui_settings()
    }
    return render_template('state.html', **templateData), 500

# Check for forced HTTPS
@app.before_request
def before_request():
    # Check for HTTPS forced (only enforce once drive mounted and stable state)
    # Otherwise, web GUI may be inaccessible if error occurs (NGINX needs drive for cert)
    if is_https_forced() and get_mynode_status() == STATE_STABLE:
        if request.url and request.url.startswith('http://'):
            app.logger.info("REDIRECTING")
            url = request.url.replace('http://', 'https://', 1)
            code = 302
            app.logger.info("Redirecting to HTTPS ({})".format(url))
            return redirect(url, code=code)

# Disable browser caching
@app.after_request
def set_response_headers(response):
    # Cache OK responses for 24 hrs
    if response.status_code in [200]:
        if "Cache-Control" not in response.headers:
            response.headers['Cache-Control'] = 'max-age=86400, private'
    else:
        # Prevents 301 from saving forever
        response.headers['Cache-Control'] = 'no-store'

    # No Caching
    #response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    #response.headers['Pragma'] = 'no-cache'
    #response.headers['Expires'] = '0'
    return response

# DEPRECATED IN FLASK 2.3 - IF EVER NEEDED, LOOK HERE
# https://stackoverflow.com/questions/73570041/flask-deprecated-before-first-request-how-to-update
#@app.before_first_request
#def before_first_request():
#    app.logger.info("BEFORE_FIRST_REQUEST START")
#
#    # Need to do anything here?
#
#    app.logger.info("BEFORE_FIRST_REQUEST END")
    

def start_threads():
    global threads
    app.logger.info("STARTING THREADS")

    # Start threads
    btc_thread1 = BackgroundThread(update_bitcoin_main_info_thread, 60) # Restart after 60, thread manages timing
    btc_thread1.start()
    threads.append(btc_thread1)
    btc_thread2 = BackgroundThread(update_bitcoin_other_info_thread, 60)
    btc_thread2.start()
    threads.append(btc_thread2)
    electrs_info_thread = BackgroundThread(update_electrs_info_thread, 60)
    electrs_info_thread.start()
    threads.append(electrs_info_thread)
    lnd_thread = BackgroundThread(update_lnd_info_thread, 60)
    lnd_thread.start()
    threads.append(lnd_thread)
    price_thread = BackgroundThread(update_price_info_thread, 60)
    price_thread.start()
    threads.append(price_thread)
    drive_thread = BackgroundThread(update_device_info, 60)
    drive_thread.start()
    threads.append(drive_thread)
    public_ip_thread = BackgroundThread(find_public_ip, 60*60*12) # 12-hour repeat
    public_ip_thread.start()
    threads.append(public_ip_thread)
    dmesg_thread = BackgroundThread(monitor_dmesg, 60) # Runs forever, restart after 60 if it fails 
    dmesg_thread.start()
    threads.append(dmesg_thread)
    app_data_cache_thread = BackgroundThread(update_application_json_cache, 300)
    app_data_cache_thread.start()
    threads.append(app_data_cache_thread)

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

    set_logger(app.logger)

    # Setup and start threads
    start_threads()

    # Register blueprints for dynamic apps
    register_dynamic_app_flask_blueprints(app)

    try:
        app.run(host='0.0.0.0', port=80)
    except ServiceExit:
        # Stop background threads
        stop_app()

    app.logger.info("Service www exiting...")
