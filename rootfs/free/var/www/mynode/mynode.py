
from config import *
from flask import Flask, render_template, Markup, send_from_directory, redirect
from bitcoind import mynode_bitcoind
from lnd import mynode_lnd, lnd_wallet_exists, is_lnd_logged_in, lnd_get, get_lnd_status
from settings import mynode_settings
from pprint import pprint
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from background_thread import BackgroundThread
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
app.register_blueprint(mynode_settings)

### Definitions
STATE_DRIVE_MISSING =       "drive_missing"
STATE_DRIVE_MOUNTED =       "drive_mounted"
STATE_QUICKSYNC_DOWNLOAD =  "quicksync_download"
STATE_QUICKSYNC_COPY =      "quicksync_copy"
STATE_QUICKSYNC_RESET =     "quicksync_reset"
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
        bitcoind_status = "Inactive"
        lnd_status_color = "red"
        lnd_ready = is_lnd_ready()
        lnd_status = "Inactive"
        
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

        templateData = {
            "title": "myNode Home",
            "config": CONFIG,
            "bitcoind_status_color": bitcoind_status_color,
            "bitcoind_status": Markup(bitcoind_status),
            "lnd_status_color": lnd_status_color,
            "lnd_status": Markup(lnd_status),
            "lnd_ready": lnd_ready,
            "drive_usage": get_drive_usage(),
            "cpu_usage": get_cpu_usage(),
            "ram_usage": get_ram_usage(),
            "swap_usage": get_swap_usage()
        }
        return render_template('main.html', **templateData)
    else:
        templateData = {
            "title": "myNode Error",
            "header_text": "Error",
            "subheader_text": "Unknown State ("+status+"). Please restart your myNode."
        }
        return render_template('state.html', **templateData)

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
        print("Killing {}".format(lnd_thread.pid))
        os.kill(lnd_thread.pid, signal.SIGKILL)
        print("Killing {}".format(drive_thread.pid))
        os.kill(drive_thread.pid, signal.SIGKILL)
        print("Killing {}".format(checkin_thread.pid))
        os.kill(checkin_thread.pid, signal.SIGKILL)

        # Shutdown Flask
        func = request.environ.get('werkzeug.server.shutdown')
        if func is None:
            raise RuntimeError('Not running with the Werkzeug Server')
        func()

    print("Service www exiting...")