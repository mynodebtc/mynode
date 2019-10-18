from config import *
from flask import Blueprint, render_template, session, abort, Markup, request, redirect, send_from_directory, url_for, flash
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
from threading import Timer
from thread_functions import *
import pam
import json
import time
import os
import subprocess

mynode_settings = Blueprint('mynode_settings',__name__)

def restart_lnd_actual():
    os.system("systemctl restart lnd")
    os.system("systemctl restart lnd_admin")

def restart_lnd():
    t = Timer(1.0, restart_lnd_actual)
    t.start()

def stop_bitcoind():
    os.system("systemctl stop bitcoind")

def stop_quicksync():
    os.system("systemctl stop quicksync")

def settings_disable_quicksync():
    stop_bitcoind()
    stop_quicksync()
    disable_quicksync()
    delete_bitcoin_data()
    delete_quicksync_data()
    reboot_device()

def settings_enable_quicksync():
    stop_bitcoind()
    stop_quicksync()
    enable_quicksync()
    delete_bitcoin_data()
    delete_quicksync_data()
    reboot_device()

def reset_bitcoin_env_file():
    os.system("echo 'BTCARGS=' > "+BITCOIN_ENV_FILE)

def delete_bitcoin_data():
    os.system("rm -rf /mnt/hdd/mynode/bitcoin")
    os.system("rm -rf /mnt/hdd/mynode/quicksync/.quicksync_complete")
    os.system("rm -rf /mnt/hdd/mynode/settings/.btcrpc_environment")
    os.system("rm -rf /mnt/hdd/mynode/settings/.btcrpcpw")

def delete_quicksync_data():
    os.system("rm -rf /mnt/hdd/mynode/quicksync")
    os.system("rm -rf /home/bitcoin/.config/transmission") # Old dir
    os.system("rm -rf /mnt/hdd/mynode/.config/transmission")

def delete_lnd_data():
    #os.system("rm -f "+LND_WALLET_FILE)
    os.system("rm -rf "+LND_DATA_FOLDER)
    os.system("rm -rf /home/bitcoin/.lnd-admin/credentials.json")
    os.system("rm -rf /mnt/hdd/mynode/settings/.lndpw")
    os.system("rm -rf /home/admin/.lnd/")
    return True

def reboot_device():
    os.system("reboot")

def shutdown_device():
    os.system("shutdown -h now")

def reset_blockchain():
    stop_bitcoind()
    delete_bitcoin_data()
    reboot_device()

def restart_quicksync():
    os.system('echo "quicksync_reset" > /mnt/hdd/mynode/.mynode_status')
    stop_bitcoind()
    stop_quicksync()
    delete_bitcoin_data()
    delete_quicksync_data()
    reboot_device()

def reset_tor():
    os.system("rm -rf /var/lib/tor/*")
    os.system("rm -rf /mnt/hdd/mynode/bitcoin/onion_private_key")
    os.system("rm -rf /mnt/hdd/mynode/lnd/v2_onion_private_key")

def factory_reset():
    # Reset subsystems that have local data
    delete_quicksync_data()

    # Delete LND data
    delete_lnd_data()

    # Delete Tor data
    reset_tor()

    # Disable services
    os.system("systemctl disable electrs --no-pager")
    os.system("systemctl disable lndhub --no-pager")
    os.system("systemctl disable btc_rpc_explorer --no-pager")
    os.system("systemctl disable vpn --no-pager")

    # Trigger drive to be reformatted on reboot
    os.system("rm -f /mnt/hdd/.mynode")

    # Reset password
    os.system("/usr/bin/mynode_chpasswd.sh bolt")

    # Reboot
    reboot_device()

def upgrade_device():
    # Upgrade
    os.system("/usr/bin/mynode_upgrade.sh")

    # Reboot
    reboot_device()

def read_ui_settings():
    ui_settings_file = '/mnt/hdd/mynode/settings/ui.json'
    if not os.path.isfile(ui_settings_file):
        # initialise UI settings
        ui_settings = {'darkmode': False}
        with open(ui_settings_file, 'w') as fp:
            json.dump(ui_settings, fp)
    else:
        with open(ui_settings_file, 'r') as fp:
            ui_settings = json.load(fp)
    return ui_settings

def write_ui_settings(ui_settings):
    ui_settings_file = '/mnt/hdd/mynode/settings/ui.json'
    with open(ui_settings_file, 'w') as fp:
        json.dump(ui_settings, fp)

def is_darkmode_enabled():
    ui_settings = read_ui_settings()
    return ui_settings['darkmode']

def disable_darkmode():
    ui_settings = read_ui_settings()
    ui_settings['darkmode'] = False
    write_ui_settings(ui_settings)

def enable_darkmode():
    ui_settings = read_ui_settings()
    ui_settings['darkmode'] = True
    write_ui_settings(ui_settings)

# Flask Pages
@mynode_settings.route("/settings")
def page_settings():

    current_version = get_current_version()
    latest_version = get_latest_version()

    changelog = get_device_changelog()
    serial_number = get_device_serial()
    device_type = get_device_type()
    product_key = get_product_key()
    pk_skipped = skipped_product_key()
    pk_error = not is_valid_product_key()
    uptime = get_system_uptime()
    local_ip = get_local_ip()
    public_ip = get_public_ip()

    quicksync_status = ""
    try:
        quicksync_status = subprocess.check_output(["mynode-get-quicksync-status"])
    except:
        quicksync_status = "ERROR"

    templateData = {
        "title": "myNode Settings",
        "password_message": "",
        "current_version": current_version,
        "latest_version": latest_version,
        "serial_number": serial_number,
        "device_type": device_type,
        "product_key": product_key,
        "product_key_skipped": pk_skipped,
        "product_key_error": pk_error,
        "changelog": changelog,
        "quicksync_status": quicksync_status,
        "is_quicksync_disabled": not is_quicksync_enabled(),
        "is_uploader_device": is_uploader(),
        "uptime": uptime,
        "public_ip": public_ip,
        "local_ip": local_ip,
        "ui_settings": read_ui_settings()
    }
    return render_template('settings.html', **templateData)

@mynode_settings.route("/settings/upgrade")
def upgrade_page():
    # Upgrade device
    t = Timer(1.0, upgrade_device)
    t.start()

    # Display wait page
    templateData = {
        "title": "myNode Upgrade",
        "header_text": "Upgrading",
        "subheader_text": "This may take a while...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/get-latest-version")
def get_latest_version_page():
    update_latest_version()
    return redirect("/settings")

@mynode_settings.route("/settings/reset-blockchain")
def reset_blockchain_page():
    t = Timer(1.0, reset_blockchain)
    t.start()
    
    # Display wait page
    templateData = {
        "title": "myNode",
        "header_text": "Reset Blockchain",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/restart-quicksync")
def restart_quicksync_page():
    t = Timer(1.0, restart_quicksync)
    t.start()

    # Display wait page
    templateData = {
        "title": "myNode",
        "header_text": "Restart Quicksync",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/reboot-device")
def reboot_device_page():
    # Trigger reboot
    t = Timer(1.0, reboot_device)
    t.start()

    # Wait until device is restarted
    templateData = {
        "title": "myNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/shutdown-device")
def shutdown_device_page():
    # Trigger shutdown
    t = Timer(1.0, shutdown_device)
    t.start()

    # Wait until device is restarted
    templateData = {
        "title": "myNode Shutdown",
        "header_text": "Shutting down...",
        "subheader_text": Markup("Your myNode is shutting down.<br/><br/>You will need to power cycle the device to turn it back on."),
        "ui_settings": read_ui_settings()
    }
    return render_template('shutdown.html', **templateData)

@mynode_settings.route("/settings/reindex-blockchain")
def reindex_blockchain_page():
    os.system("echo 'BTCARGS=-reindex-chainstate' > "+BITCOIN_ENV_FILE)
    os.system("systemctl restart bitcoind")
    t = Timer(30.0, reset_bitcoin_env_file)
    t.start()
    return redirect("/settings")

@mynode_settings.route("/settings/rescan-blockchain")
def rescan_blockchain_page():
    os.system("echo 'BTCARGS=-rescan' > "+BITCOIN_ENV_FILE)
    os.system("systemctl restart bitcoind")
    t = Timer(30.0, reset_bitcoin_env_file)
    t.start()
    return redirect("/settings")

@mynode_settings.route("/settings/factory-reset", methods=['POST'])
def factory_reset_page():
    p = pam.pam()
    pw = request.form.get('password_factory_reset')
    if pw == None or p.authenticate("admin", pw) == False:
        flash("Invalid Password", category="error")
        return redirect(url_for(".page_settings"))
    else:
        t = Timer(2.0, factory_reset)
        t.start()

        templateData = {
            "title": "myNode Factory Reset",
            "header_text": "Factory Reset",
            "subheader_text": "This will take several minutes...",
            "ui_settings": read_ui_settings()
        }
        return render_template('reboot.html', **templateData)


@mynode_settings.route("/settings/password", methods=['POST'])
def change_password_page():
    if not request:
        return redirect("/settings")

    # Verify current password
    p = pam.pam()
    current = request.form.get('current_password')
    if current == None or p.authenticate("admin", current) == False:
        flash("Invalid Password", category="error")
        return redirect(url_for(".page_settings"))

    p1 = request.form.get('password1')
    p2 = request.form.get('password2')

    if p1 == None or p2 == None or p1 == "" or p2 == "" or p1 != p2:
        flash("Passwords did not match or were empty!", category="error")
        return redirect(url_for(".page_settings"))
    else:
        # Change password
        subprocess.call(['/usr/bin/mynode_chpasswd.sh', p1])

    flash("Password Updated!", category="message")
    return redirect(url_for(".page_settings"))


@mynode_settings.route("/settings/delete-lnd-wallet", methods=['POST'])
def page_lnd_delete_wallet():
    p = pam.pam()
    pw = request.form.get('password_lnd_delete')
    if pw == None or p.authenticate("admin", pw) == False:
        flash("Invalid Password", category="error")
        return redirect(url_for(".page_settings"))
    else:
        # Successful Auth
        delete_lnd_data()
        restart_lnd()

    flash("Lightning wallet deleted!", category="message")
    return redirect(url_for(".page_settings"))

@mynode_settings.route("/settings/reset-tor", methods=['POST'])
def page_reset_tor():
    p = pam.pam()
    pw = request.form.get('password_reset_tor')
    if pw == None or p.authenticate("admin", pw) == False:
        flash("Invalid Password", category="error")
        return redirect(url_for(".page_settings"))
    else:
        # Successful Auth
        reset_tor()

        # Trigger reboot
        t = Timer(1.0, reboot_device)
        t.start()

    # Wait until device is restarted
    templateData = {
        "title": "myNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/mynode_logs.tar.gz")
def download_logs_page():
    os.system("rm -rf /tmp/mynode_logs.tar.gz")
    os.system("rm -rf /tmp/mynode_info/")
    os.system("mkdir -p /tmp/mynode_info/")
    os.system("mynode-get-quicksync-status > /tmp/mynode_info/quicksync_state.txt")
    os.system("cp /usr/share/version /tmp/mynode_info/version")
    os.system("tar -czvf /tmp/mynode_logs.tar.gz /var/log/ /tmp/mynode_info/")
    return send_from_directory(directory="/tmp/", filename="mynode_logs.tar.gz")

@mynode_settings.route("/settings/repair-drive")
def repair_drive_page():
    # Touch files to trigger re-checking drive
    os.system("touch /home/bitcoin/.mynode/check_drive")
    os.system("sync")
    
    # Trigger reboot
    t = Timer(1.0, reboot_device)
    t.start()

    # Wait until device is restarted
    templateData = {
        "title": "myNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/toggle-uploader")
def toggle_uploader_page():
    # Toggle uploader
    if is_uploader():
        unset_uploader()
    else:
        set_uploader()

    # Trigger reboot
    t = Timer(1.0, reboot_device)
    t.start()

    # Wait until device is restarted
    templateData = {
        "title": "myNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/toggle-quicksync")
def toggle_quicksync_page():
    # Toggle uploader
    if is_quicksync_enabled():
        t = Timer(1.0, settings_disable_quicksync)
        t.start()
    else:
        t = Timer(1.0, settings_enable_quicksync)
        t.start()

    # Wait until device is restarted
    templateData = {
        "title": "myNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/ping")
def ping_page():
    return "alive"

@mynode_settings.route("/settings/toggle-darkmode")
def toggle_darkmode_page():
    if is_darkmode_enabled():
        disable_darkmode()
    else:
        enable_darkmode()
    return redirect("/settings")