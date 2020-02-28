from config import *
from flask import Blueprint, render_template, session, abort, Markup, request, redirect, send_from_directory, url_for, flash
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from bitcoind import is_bitcoind_synced
from pprint import pprint, pformat
from threading import Timer
from thread_functions import *
from user_management import check_logged_in
from lightning_info import *
from thread_functions import *
import pam
import json
import time
import os
import subprocess

mynode_settings = Blueprint('mynode_settings',__name__)

def read_ui_settings():
    ui_hdd_file = '/mnt/hdd/mynode/settings/ui.json'
    ui_mynode_file = '/home/bitcoin/.mynode/ui.json'

    # read ui.json from HDD
    if os.path.isfile(ui_hdd_file):
        with open(ui_hdd_file, 'r') as fp:
            ui_settings = json.load(fp)
    # read ui.json from mynode
    elif os.path.isfile(ui_mynode_file):
        with open(ui_mynode_file, 'r') as fp:
            ui_settings = json.load(fp)
    # if ui.json is not found anywhere, use default settings
    else:
        ui_settings = {'darkmode': False}

    return ui_settings

def write_ui_settings(ui_settings):
    ui_hdd_file = '/mnt/hdd/mynode/settings/ui.json'
    ui_mynode_file = '/home/bitcoin/.mynode/ui.json'

    try:
        with open(ui_hdd_file, 'w') as fp:
            json.dump(ui_settings, fp)
    except:
        pass

    with open(ui_mynode_file, 'w') as fp:
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
    check_logged_in()

    current_version = get_current_version()
    latest_version = get_latest_version()
    current_beta_version = get_current_beta_version()
    latest_beta_version = get_latest_beta_version()

    changelog = get_device_changelog()
    serial_number = get_device_serial()
    device_type = get_device_type()
    product_key = get_product_key()
    pk_skipped = skipped_product_key()
    pk_error = not is_valid_product_key()
    uptime = get_system_uptime()
    date = get_system_date()
    local_ip = get_local_ip()
    public_ip = get_public_ip()


    # Get Startup Status
    startup_status_log = get_journalctl_log("mynode")

    # Get QuickSync Status
    quicksync_enabled = is_quicksync_enabled()
    quicksync_status = "Disabled"
    quicksync_status_color = "gray"
    quicksync_status_log = "DISABLED"
    if quicksync_enabled:
        quicksync_status = get_service_status_basic_text("quicksync")
        quicksync_status_color = get_service_status_color("quicksync")
        try:
            quicksync_status_log = subprocess.check_output(["mynode-get-quicksync-status"]).decode("utf8")
        except:
            quicksync_status_log = "ERROR"

    # Get Bitcoin Status
    bitcoin_status_log = ""
    try:
        bitcoin_status_log = subprocess.check_output(["tail","-n","200","/mnt/hdd/mynode/bitcoin/debug.log"]).decode("utf8")
        lines = bitcoin_status_log.split('\n')
        lines.reverse()
        bitcoin_status_log = '\n'.join(lines)
    except:
        bitcoin_status_log = "ERROR"

    # Get LND Status
    lnd_status_log = get_journalctl_log("lnd")

    # Get Tor Status
    tor_status_log = get_journalctl_log("tor@default")

    # Get Electrs Status
    electrs_status_log = get_journalctl_log("electrs")

    # Get RTL Status
    rtl_status_log = get_journalctl_log("rtl")

    # Get Docker Status
    docker_status_log = get_journalctl_log("docker")

    # Get Docker Image Build Status
    docker_image_build_status_log = get_journalctl_log("docker_images")

    # Get QuickSync Rates
    upload_rate = 100
    download_rate = 100
    try:
        upload_rate = subprocess.check_output(["cat","/mnt/hdd/mynode/settings/quicksync_upload_rate"])
        download_rate = subprocess.check_output(["cat","/mnt/hdd/mynode/settings/quicksync_background_download_rate"])
    except:
        upload_rate = 100
        download_rate = 100


    templateData = {
        "title": "myNode Settings",
        "password_message": "",
        "current_version": current_version,
        "latest_version": latest_version,
        "current_beta_version": current_beta_version,
        "latest_beta_version": latest_beta_version,
        "upgrade_error": did_upgrade_fail(),
        "upgrade_logs": get_recent_upgrade_logs(),
        "serial_number": serial_number,
        "device_type": device_type,
        "product_key": product_key,
        "product_key_skipped": pk_skipped,
        "product_key_error": pk_error,
        "changelog": changelog,
        "startup_status_log": startup_status_log,
        "startup_status": get_service_status_basic_text("mynode"),
        "startup_status_color": get_service_status_color("mynode"),
        "quicksync_status_log": quicksync_status_log,
        "quicksync_status": quicksync_status,
        "quicksync_status_color": quicksync_status_color,
        "is_bitcoin_synced": is_bitcoind_synced(),
        "bitcoin_status_log": bitcoin_status_log,
        "bitcoin_status": get_service_status_basic_text("bitcoind"),
        "bitcoin_status_color": get_service_status_color("bitcoind"),
        "lnd_status_log": lnd_status_log,
        "lnd_status": get_service_status_basic_text("lnd"),
        "lnd_status_color": get_service_status_color("lnd"),
        "tor_status_log": tor_status_log,
        "tor_status": get_service_status_basic_text("tor@default"),
        "tor_status_color": get_service_status_color("tor@default"),
        "electrs_status_log": electrs_status_log,
        "electrs_status": get_service_status_basic_text("electrs"),
        "electrs_status_color": get_service_status_color("electrs"),
        "rtl_status_log": rtl_status_log,
        "rtl_status": get_service_status_basic_text("rtl"),
        "rtl_status_color": get_service_status_color("rtl"),
        "docker_status_log": docker_status_log,
        "docker_status": get_service_status_basic_text("docker"),
        "docker_status_color": get_service_status_color("docker"),
        "docker_image_build_status_log": docker_image_build_status_log,
        "docker_image_build_status": get_docker_image_build_status(),
        "docker_image_build_status_color": get_docker_image_build_status_color(),
        "btcpayserver_status_log": get_journalctl_log("btcpayserver"),
        "btcpayserver_status": get_service_status_basic_text("btcpayserver"),
        "btcpayserver_status_color": get_service_status_color("btcpayserver"),
        "mempoolspace_status_log": get_journalctl_log("mempoolspace"),
        "mempoolspace_status": get_service_status_basic_text("mempoolspace"),
        "mempoolspace_status_color": get_service_status_color("mempoolspace"),
        "firewall_status_log": get_journalctl_log("ufw"),
        "firewall_status": get_service_status_basic_text("ufw"),
        "firewall_status_color": get_service_status_color("ufw"),
        "firewall_rules": get_firewall_rules(),
        "is_quicksync_disabled": not quicksync_enabled,
        "is_netdata_enabled": is_netdata_enabled(),
        "is_uploader_device": is_uploader(),
        "download_rate": download_rate,
        "upload_rate": upload_rate,
        "is_btc_lnd_tor_enabled": is_btc_lnd_tor_enabled(),
        "uptime": uptime,
        "date": date,
        "public_ip": public_ip,
        "local_ip": local_ip,
        "drive_usage": get_drive_usage(),
        "cpu_usage": get_cpu_usage(),
        "ram_usage": get_ram_usage(),
        "device_temp": get_device_temp(),
        "ui_settings": read_ui_settings()
    }
    return render_template('settings.html', **templateData)

@mynode_settings.route("/settings/upgrade")
def upgrade_page():
    check_logged_in()

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

@mynode_settings.route("/settings/upgrade-beta")
def upgrade_beta_page():
    check_logged_in()

    # Upgrade device
    t = Timer(1.0, upgrade_device_beta)
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
    check_logged_in()
    update_latest_version()
    return redirect("/settings")

@mynode_settings.route("/settings/check-in")
def check_in_page():
    check_logged_in()
    check_in()
    return redirect("/settings")

@mynode_settings.route("/settings/reset-blockchain")
def reset_blockchain_page():
    check_logged_in()
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
    check_logged_in()
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
    check_logged_in()

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
    check_logged_in()

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
    check_logged_in()
    os.system("echo 'BTCARGS=-reindex-chainstate' > "+BITCOIN_ENV_FILE)
    os.system("systemctl restart bitcoind")
    t = Timer(30.0, reset_bitcoin_env_file)
    t.start()
    return redirect("/settings")

@mynode_settings.route("/settings/rescan-blockchain")
def rescan_blockchain_page():
    check_logged_in()
    os.system("echo 'BTCARGS=-rescan' > "+BITCOIN_ENV_FILE)
    os.system("systemctl restart bitcoind")
    t = Timer(30.0, reset_bitcoin_env_file)
    t.start()
    return redirect("/settings")

@mynode_settings.route("/settings/reset-electrs")
def reset_electrs_page():
    check_logged_in()
    t = Timer(1.0, reset_electrs)
    t.start()

    # Display wait page
    templateData = {
        "title": "myNode",
        "header_text": "Resetting Electrum Data",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/reset-firewall")
def reset_firewall_page():
    check_logged_in()
    t = Timer(3.0, reload_firewall)
    t.start()
    flash("Firewall Reset", category="message")
    return redirect("/settings")

@mynode_settings.route("/settings/factory-reset", methods=['POST'])
def factory_reset_page():
    check_logged_in()
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
    check_logged_in()
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


@mynode_settings.route("/settings/quicksync_rates", methods=['POST'])
def change_quicksync_rates_page():
    check_logged_in()
    if not request:
        return redirect("/settings")

    downloadRate = request.form.get('download-rate')
    uploadRate = request.form.get('upload-rate')

    os.system("echo {} > /mnt/hdd/mynode/settings/quicksync_upload_rate".format(uploadRate))
    os.system("echo {} > /mnt/hdd/mynode/settings/quicksync_background_download_rate".format(downloadRate))
    os.system("sync")
    os.system("systemctl restart bandwidth")

    flash("QuickSync Rates Updated!", category="message")
    return redirect(url_for(".page_settings"))


@mynode_settings.route("/settings/delete-lnd-wallet", methods=['POST'])
def page_lnd_delete_wallet():
    check_logged_in()
    p = pam.pam()
    pw = request.form.get('password_lnd_delete')
    if pw == None or p.authenticate("admin", pw) == False:
        flash("Invalid Password", category="error")
        return redirect(url_for(".page_settings"))

    # Successful Auth
    delete_lnd_data()
    
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


@mynode_settings.route("/settings/reset-tor", methods=['POST'])
def page_reset_tor():
    check_logged_in()
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

@mynode_settings.route("/settings/enable_btc_lnd_tor")
def page_enable_btc_lnd_tor():
    check_logged_in()
    
    enable = request.args.get('enable')
    if enable == "1":
        enable_btc_lnd_tor()
    else:
        disable_btc_lnd_tor()

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
    check_logged_in()

    os.system("/usr/bin/mynode_gen_debug_tarball.sh")

    return send_from_directory(directory="/tmp/", filename="mynode_logs.tar.gz")

@mynode_settings.route("/settings/regen-https-certs")
def regen_https_certs_page():
    check_logged_in()

    # Touch files to trigger re-checking drive
    os.system("rm -rf /home/bitcoin/.mynode/https")
    os.system("rm -rf /mnt/hdd/mynode/settings/https")
    os.system("sync")
    os.system("systemctl restart https")
    
    flash("HTTPS Service Restarted", category="message")
    return redirect(url_for(".page_settings"))

@mynode_settings.route("/settings/regen-electrs-certs")
def regen_electrs_certs_page():
    check_logged_in()

    # Touch files to trigger re-checking drive
    os.system("rm -rf /home/bitcoin/.mynode/electrs")
    os.system("rm -rf /mnt/hdd/mynode/settings/electrs")
    os.system("sync")
    os.system("systemctl restart tls_proxy")
    
    flash("Electrum Server Service Restarted", category="message")
    return redirect(url_for(".page_settings"))

@mynode_settings.route("/settings/reinstall-app")
def reinstall_app_page():
    check_logged_in()

    app = request.args.get('app')

    # Re-install app
    t = Timer(1.0, reinstall_app, [app])
    t.start()

    # Display wait page
    templateData = {
        "title": "myNode Install",
        "header_text": "Installing",
        "subheader_text": "This may take a while...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/toggle-uploader")
def toggle_uploader_page():
    check_logged_in()
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
    check_logged_in()
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

@mynode_settings.route("/settings/toggle-netdata")
def toggle_netdata_page():
    if is_netdata_enabled():
        disable_netdata()
    else:
        enable_netdata()
    return redirect("/settings")