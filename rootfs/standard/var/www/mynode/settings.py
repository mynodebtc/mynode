from config import *
from flask import Blueprint, render_template, session, abort, Markup, request, redirect, send_from_directory, url_for, flash, current_app
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from bitcoin import is_bitcoin_synced
from bitcoin_info import using_bitcoin_custom_config
from lightning_info import using_lnd_custom_config
from pprint import pprint, pformat
from threading import Timer
from thread_functions import *
from user_management import check_logged_in
from lightning_info import *
from thread_functions import *
from utilities import *
from application_info import *
import pam
import time
import os
import subprocess

mynode_settings = Blueprint('mynode_settings',__name__)

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
    device_arch = get_device_arch()
    device_ram = get_device_ram()
    product_key = get_product_key()
    pk_skipped = skipped_product_key()
    pk_error = not is_valid_product_key()
    uptime = get_system_uptime()
    date = get_system_date()
    local_ip = get_local_ip()

    # Get QuickSync Rates
    upload_rate = 100
    download_rate = 100
    try:
        upload_rate = subprocess.check_output(["cat","/mnt/hdd/mynode/settings/quicksync_upload_rate"])
        download_rate = subprocess.check_output(["cat","/mnt/hdd/mynode/settings/quicksync_background_download_rate"])
    except:
        upload_rate = 100
        download_rate = 100

    logout_time_days, logout_time_hours = get_flask_session_timeout()

    t1 = get_system_time_in_ms()
    all_logs = get_all_upgrade_logs()
    t2 = get_system_time_in_ms()

    templateData = {
        "title": "myNode Settings",
        "load_time": t2-t1,
        "apps": get_all_applications(order_by="alphabetic"),
        "password_message": "",
        "current_version": current_version,
        "latest_version": latest_version,
        "current_beta_version": current_beta_version,
        "latest_beta_version": latest_beta_version,
        "has_checkin_error": has_checkin_error(),
        "upgrade_error": did_upgrade_fail(),
        "upgrade_log": get_recent_upgrade_log(),
        "upgrade_logs": get_all_upgrade_logs(),
        "serial_number": serial_number,
        "device_type": device_type,
        "device_arch": device_arch,
        "device_ram": device_ram,
        "swap_size": get_swap_size(),
        "product_key": product_key,
        "product_key_skipped": pk_skipped,
        "product_key_error": pk_error,
        "changelog": changelog,
        "is_https_forced": is_https_forced(),
        "logout_time_days": logout_time_days,
        "logout_time_hours": logout_time_hours,
        "using_bitcoin_custom_config": using_bitcoin_custom_config(),
        "using_lnd_custom_config": using_lnd_custom_config(),
        "is_bitcoin_synced": is_bitcoin_synced(),
        "is_installing_docker_images": is_installing_docker_images(),
        "firewall_rules": get_firewall_rules(),
        "is_testnet_enabled": is_testnet_enabled(),
        "is_quicksync_disabled": not is_quicksync_enabled(),
        "netdata_enabled": is_service_enabled("netdata"),
        "is_uploader_device": is_uploader(),
        "download_rate": download_rate,
        "upload_rate": upload_rate,
        "is_btc_lnd_tor_enabled": is_btc_lnd_tor_enabled(),
        "is_aptget_tor_enabled": is_aptget_tor_enabled(),
        "skip_fsck": skip_fsck(),
        "uptime": uptime,
        "date": date,
        "local_ip": local_ip,
        "throttled_data": get_throttled_data(),
        "oom_error": has_oom_error(),
        "oom_info": get_oom_error_info(),
        "drive_usage": get_drive_usage(),
        "cpu_usage": get_cpu_usage(),
        "ram_usage": get_ram_usage(),
        "device_temp": get_device_temp(),
        "ui_settings": read_ui_settings()
    }
    return render_template('settings.html', **templateData)

@mynode_settings.route("/status")
def page_status():
    check_logged_in()
    t1 = get_system_time_in_ms()

    current_version = get_current_version()
    latest_version = get_latest_version()
    current_beta_version = get_current_beta_version()
    latest_beta_version = get_latest_beta_version()

    changelog = get_device_changelog()
    serial_number = get_device_serial()
    device_type = get_device_type()
    device_arch = get_device_arch()
    device_ram = get_device_ram()
    product_key = get_product_key()
    pk_skipped = skipped_product_key()
    pk_error = not is_valid_product_key()
    uptime = get_system_uptime()
    date = get_system_date()
    local_ip = get_local_ip()


    # Get Startup Status
    #startup_status_log = get_journalctl_log("mynode")

    # Get QuickSync Status
    quicksync_enabled = is_quicksync_enabled()
    quicksync_status = "Disabled"
    quicksync_status_color = "gray"
    quicksync_status_log = get_quicksync_log()
    if quicksync_enabled:
        quicksync_status = get_service_status_basic_text("quicksync")
        quicksync_status_color = get_service_status_color("quicksync")

    # Get Bitcoin Status
    # bitcoin_status_log = get_file_log( get_bitcoin_log_file() )
    # GET lnd, loop, pool logs from file???
    #lnd_status_log = get_file_log("/mnt/hdd/mynode/lnd/logs/bitcoin/mainnet/lnd.log")
    #loop_status_log = get_file_log("/mnt/hdd/mynode/loop/logs/mainnet/loopd.log")
    #pool_status_log = get_file_log("/mnt/hdd/mynode/pool/logs/mainnet/poold.log")

    # Get Status
    # lnd_status_log = get_journalctl_log("lnd")
    # loop_status_log = get_journalctl_log("loop")
    # pool_status_log = get_journalctl_log("pool")
    # lndhub_status_log = get_journalctl_log("lndhub")
    # tor_status_log = get_journalctl_log("tor@default")
    # electrs_status_log = get_journalctl_log("electrs")
    # netdata_status_log = get_journalctl_log("netdata")
    # rtl_status_log = get_journalctl_log("rtl")
    # lnbits_status_log = get_journalctl_log("lnbits")
    # thunderhub_status_log = get_journalctl_log("thunderhub")
    # ckbunker_status_log = get_journalctl_log("ckbunker")
    # sphinxrelay_status_log = get_journalctl_log("sphinxrelay")
    # docker_status_log = get_journalctl_log("docker")
    # docker_image_build_status_log = get_journalctl_log("docker_images")

    # Find running containers
    running_containers = get_docker_running_containers()

    templateData = {
        "title": "myNode Status",
        "password_message": "",
        "current_version": current_version,
        "latest_version": latest_version,
        "current_beta_version": current_beta_version,
        "latest_beta_version": latest_beta_version,
        "has_checkin_error": has_checkin_error(),
        "upgrade_error": did_upgrade_fail(),
        "upgrade_logs": get_recent_upgrade_log(),
        "serial_number": serial_number,
        "device_type": device_type,
        "device_arch": device_arch,
        "device_ram": device_ram,
        "product_key": product_key,
        "product_key_skipped": pk_skipped,
        "product_key_error": pk_error,
        "changelog": changelog,
        "lnd_wallet_exists": lnd_wallet_exists(),
        "lnd_ready": is_lnd_ready(),
        "is_installing_docker_images": is_installing_docker_images(),
        "running_containers": running_containers,
        #"startup_status_log": startup_status_log,
        "startup_status": get_service_status_basic_text("mynode"),
        "startup_status_color": get_service_status_color("mynode"),
        #"quicksync_status_log": quicksync_status_log,
        "quicksync_status": quicksync_status,
        "quicksync_status_color": quicksync_status_color,
        "is_bitcoin_synced": is_bitcoin_synced(),
        #"bitcoin_status_log": bitcoin_status_log,
        "bitcoin_status": get_service_status_basic_text("bitcoin"),
        "bitcoin_status_color": get_service_status_color("bitcoin"),
        #"lnd_status_log": lnd_status_log,
        "lnd_status": get_service_status_basic_text("lnd"),
        "lnd_status_color": get_service_status_color("lnd"),
        #"loop_status_log": loop_status_log,
        "loop_status": get_service_status_basic_text("loop"),
        "loop_status_color": get_service_status_color("loop"),
        #"pool_status_log": pool_status_log,
        "pool_status": get_service_status_basic_text("pool"),
        "pool_status_color": get_service_status_color("pool"),
        #"lit_status_log": get_journalctl_log("lit"),
        "lit_status": get_service_status_basic_text("lit"),
        "lit_status_color": get_service_status_color("lit"),
        #"tor_status_log": tor_status_log,
        "tor_status": get_service_status_basic_text("tor@default"),
        "tor_status_color": get_service_status_color("tor@default"),
        #"lndhub_status_log": lndhub_status_log,
        "lndhub_status": get_service_status_basic_text("lndhub"),
        "lndhub_status_color": get_service_status_color("lndhub"),
        #"netdata_status_log": netdata_status_log,
        "netdata_status": get_service_status_basic_text("netdata"),
        "netdata_status_color": get_service_status_color("netdata"),
        #"electrs_status_log": electrs_status_log,
        "electrs_status": get_service_status_basic_text("electrs"),
        "electrs_status_color": get_service_status_color("electrs"),
        #"rtl_status_log": rtl_status_log,
        "rtl_status": get_service_status_basic_text("rtl"),
        "rtl_status_color": get_service_status_color("rtl"),
        #"lnbits_status_log": lnbits_status_log,
        "lnbits_status": get_service_status_basic_text("lnbits"),
        "lnbits_status_color": get_service_status_color("lnbits"),
        #"thunderhub_status_log": thunderhub_status_log,
        "thunderhub_status": get_service_status_basic_text("thunderhub"),
        "thunderhub_status_color": get_service_status_color("thunderhub"),
        #"ckbunker_status_log": ckbunker_status_log,
        "ckbunker_status": get_service_status_basic_text("ckbunker"),
        "ckbunker_status_color": get_service_status_color("ckbunker"),
        #"sphinxrelay_status_log": sphinxrelay_status_log,
        "sphinxrelay_status": get_service_status_basic_text("sphinxrelay"),
        "sphinxrelay_status_color": get_service_status_color("sphinxrelay"),
        #"docker_status_log": docker_status_log,
        "docker_status": get_service_status_basic_text("docker"),
        "docker_status_color": get_service_status_color("docker"),
        #"docker_image_build_status_log": docker_image_build_status_log,
        "docker_image_build_status": get_docker_image_build_status(),
        "docker_image_build_status_color": get_docker_image_build_status_color(),
        #"whirlpool_status_log": get_journalctl_log("whirlpool"),
        "whirlpool_status": get_service_status_basic_text("whirlpool"),
        "whirlpool_status_color": get_service_status_color("whirlpool"),
        #"dojo_status_log": get_journalctl_log("dojo"),
        "dojo_status": get_service_status_basic_text("dojo"),
        "dojo_status_color": get_service_status_color("dojo"),
        #"btcpayserver_status_log": get_journalctl_log("btcpayserver"),
        "btcpayserver_status": get_service_status_basic_text("btcpayserver"),
        "btcpayserver_status_color": get_service_status_color("btcpayserver"),
        #"mempool_status_log": get_journalctl_log("mempool"),
        "mempool_status": get_service_status_basic_text("mempool"),
        "mempool_status_color": get_service_status_color("mempool"),
        #"caravan_status_log": get_journalctl_log("caravan"),
        "caravan_status": get_service_status_basic_text("caravan"),
        "caravan_status_color": get_service_status_color("caravan"),
        #"specter_status_log": get_journalctl_log("specter"),
        "specter_status": get_service_status_basic_text("specter"),
        "specter_status_color": get_service_status_color("specter"),
        #"nginx_status_log": get_journalctl_log("nginx"),
        "nginx_status": get_service_status_basic_text("nginx"),
        "nginx_status_color": get_service_status_color("nginx"),
        #"www_status_log": get_journalctl_log("www"),
        "www_status": get_service_status_basic_text("www"),
        "www_status_color": get_service_status_color("www"),
        #"ufw_status_log": get_journalctl_log("ufw"),
        "ufw_status": get_service_status_basic_text("ufw"),
        "ufw_status_color": get_service_status_color("ufw"),
        "firewall_rules": get_firewall_rules(),
        "is_quicksync_disabled": not quicksync_enabled,
        "netdata_enabled": is_service_enabled("netdata"),
        "uptime": uptime,
        "date": date,
        "local_ip": local_ip,
        "throttled_data": get_throttled_data(),
        "oom_error": has_oom_error(),
        "oom_info": get_oom_error_info(),
        "drive_usage": get_drive_usage(),
        "cpu_usage": get_cpu_usage(),
        "ram_usage": get_ram_usage(),
        "device_temp": get_device_temp(),
        "ui_settings": read_ui_settings()
    }
    t2 = get_system_time_in_ms()
    templateData["load_time"] = t2-t1
    return render_template('status.html', **templateData)

@mynode_settings.route("/settings/upgrade")
def upgrade_page():
    check_logged_in()

    check_and_mark_reboot_action("upgrade")

    # Upgrade device
    t = Timer(1.0, upgrade_device)
    t.start()

    # Display wait page
    templateData = {
        "title": "myNode Upgrade",
        "header_text": "Upgrading",
        "subheader_text": "This may take a while...",
        "show_upgrade_log": True,
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/upgrade-beta")
def upgrade_beta_page():
    check_logged_in()

    check_and_mark_reboot_action("upgrade_beta")

    # Upgrade device
    t = Timer(1.0, upgrade_device_beta)
    t.start()

    # Display wait page
    templateData = {
        "title": "myNode Upgrade",
        "header_text": "Upgrading",
        "subheader_text": "This may take a while...",
        "show_upgrade_log": True,
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/get-upgrade-log-raw")
def get_upgrade_log_page():
    check_logged_in()

    log = get_file_contents("/home/admin/upgrade_logs/upgrade_log_latest.txt").decode("utf8")
    if (log == "ERROR"):
        log = "No log file found"
        
    log = cleanup_log(log)
    return log

@mynode_settings.route("/settings/clear-upgrade-logs")
def clear_upgrade_logs_page():
    check_logged_in()

    os.system("rm -f /home/admin/upgrade_logs/*")

    flash("Upgrade Logs Cleared", category="message")
    return redirect("/settings")

@mynode_settings.route("/settings/upgrade-test")
def upgrade_page_test():
    check_logged_in()

    # Display wait page
    templateData = {
        "title": "myNode Upgrade",
        "header_text": "Upgrading",
        "subheader_text": "This may take a while...",
        "show_upgrade_log": True,
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

    check_and_mark_reboot_action("reset_blockchain")

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

    check_and_mark_reboot_action("restart_quicksync")

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

@mynode_settings.route("/settings/reboot-device-no-format")
def reboot_device_no_format_page():
    check_logged_in()

    os.system("rm -f /home/bitcoin/.mynode/force_format_prompt")

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
        "ui_settings": read_ui_settings()
    }
    return render_template('shutdown.html', **templateData)

@mynode_settings.route("/settings/reindex-blockchain")
def reindex_blockchain_page():
    check_logged_in()
    os.system("echo 'BTCARGS=-reindex-chainstate' > "+BITCOIN_ENV_FILE)
    os.system("systemctl restart bitcoin")
    t = Timer(30.0, reset_bitcoin_env_file)
    t.start()
    return redirect("/settings")

@mynode_settings.route("/settings/rescan-blockchain")
def rescan_blockchain_page():
    check_logged_in()
    os.system("echo 'BTCARGS=-rescan' > "+BITCOIN_ENV_FILE)
    os.system("systemctl restart bitcoin")
    t = Timer(30.0, reset_bitcoin_env_file)
    t.start()
    return redirect("/settings")

@mynode_settings.route("/settings/reset-docker")
def reset_docker_page():
    check_logged_in()

    check_and_mark_reboot_action("reset_docker")

    t = Timer(1.0, reset_docker)
    t.start()

    # Display wait page
    templateData = {
        "title": "myNode",
        "header_text": "Resetting Docker Data",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/open-clone-tool")
def open_clone_tool_page():
    check_logged_in()

    check_and_mark_reboot_action("open_clone_tool")

    os.system("touch /home/bitcoin/open_clone_tool")
    os.system("sync")

    # Trigger reboot
    t = Timer(1.0, reboot_device)
    t.start()

    # Display wait page
    templateData = {
        "title": "myNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "Restarting to Open Clone Tool....",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/reset-electrs")
def reset_electrs_page():
    check_logged_in()

    t = Timer(1.0, reset_electrs)
    t.start()

    flash("Resetting Electrum Server data...", category="message")
    return redirect("/settings")

@mynode_settings.route("/settings/clear-mempool-cache")
def clear_mempool_cache_page():
    check_logged_in()

    t = Timer(1.0, clear_mempool_cache)
    t.start()

    flash("Mempool Cache Cleared", category="message")
    return redirect("/settings")

@mynode_settings.route("/settings/reset-specter-config")
def reset_specter_config_page():
    check_logged_in()

    t = Timer(1.0, reset_specter_config)
    t.start()

    flash("Specter Configuration Reset", category="message")
    return redirect("/settings")

@mynode_settings.route("/settings/reset-firewall")
def reset_firewall_page():
    check_logged_in()
    t = Timer(3.0, reload_firewall)
    t.start()
    flash("Firewall Reset", category="message")
    return redirect("/settings")

@mynode_settings.route("/settings/refresh-app-database")
def refresh_app_database_page():
    check_logged_in()
    
    trigger_application_refresh()

    flash("Application Database Refreshed", category="message")
    return redirect("/settings")

@mynode_settings.route("/settings/remount-external-drive")
def remount_external_drive_page():
    os.system("mount -o remount,rw /mnt/hdd")
    flash("Remounted External Drive", category="message")
    return redirect("/settings")

@mynode_settings.route("/settings/format-external-drive", methods=['POST'])
def format_external_drive_page():
    check_logged_in()
    p = pam.pam()
    pw = request.form.get('password_format_external_drive')
    if pw == None or p.authenticate("admin", pw) == False:
        flash("Invalid Password", category="error")
        return redirect(url_for(".page_settings"))
    else:
        check_and_mark_reboot_action("format_external_drive")

        os.system("touch /home/bitcoin/.mynode/force_format_prompt")

        templateData = {
            "title": "myNode",
            "header_text": "Rebooting",
            "subheader_text": "This will take several minutes...",
            "ui_settings": read_ui_settings()
        }
        return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/factory-reset", methods=['POST'])
def factory_reset_page():
    check_logged_in()
    p = pam.pam()
    pw = request.form.get('password_factory_reset')
    if pw == None or p.authenticate("admin", pw) == False:
        flash("Invalid Password", category="error")
        return redirect(url_for(".page_settings"))
    else:
        check_and_mark_reboot_action("factory_reset")

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


@mynode_settings.route("/settings/logout_time", methods=['POST'])
def change_logout_time_page():
    check_logged_in()
    if not request:
        return redirect("/settings")

    d = request.form.get('logout_days')
    h = request.form.get('logout_hours')

    if d == "0" and h == "0":
        flash("Logout time cannot be 0 hours and 0 days", category="error")
        return redirect(url_for(".page_settings"))

    set_flask_session_timeout(d, h)
    
    # Trigger reboot
    t = Timer(3.0, restart_flask)
    t.start()

    flash("Automatic logout time updated!", category="message")
    return redirect(url_for(".page_settings"))


@mynode_settings.route("/settings/delete-lnd-wallet", methods=['POST'])
def page_lnd_delete_wallet():
    check_logged_in()
    p = pam.pam()
    pw = request.form.get('password_lnd_delete')
    if pw == None or p.authenticate("admin", pw) == False:
        flash("Invalid Password", category="error")
        return redirect(url_for(".page_settings"))

    check_and_mark_reboot_action("delete_lnd_data")

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
        check_and_mark_reboot_action("reset_tor")

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

    check_and_mark_reboot_action("enable_btc_lnd_tor")
    
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

@mynode_settings.route("/settings/set_https_forced")
def page_set_https_forced_page():
    check_logged_in()
    
    forced = request.args.get('forced')
    if forced == "1":
        force_https(True)
    else:
        force_https(False)

    flash("HTTPS Settings Saved", category="message")
    return redirect(url_for(".page_settings"))
    

@mynode_settings.route("/settings/enable_aptget_tor")
def page_enable_aptget_tor():
    check_logged_in()

    check_and_mark_reboot_action("enable_aptget_tor")
    
    enable = request.args.get('enable')
    if enable == "1":
        enable_aptget_tor()
    else:
        disable_aptget_tor()
    return redirect(url_for(".page_settings"))

@mynode_settings.route("/settings/mynode_logs.tar.gz")
def download_logs_page():
    check_logged_in()

    os.system("/usr/bin/mynode_gen_debug_tarball.sh")

    return send_from_directory(directory="/tmp/", filename="mynode_logs.tar.gz")

@mynode_settings.route("/settings/regen-https-certs")
def regen_https_certs_page():
    check_logged_in()

    # Re-install app
    t = Timer(1.0, regen_https_cert)
    t.start()
    
    flash("HTTPS Service Restarting", category="message")
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

    check_and_mark_reboot_action("reinstall_app")

    # Check application specified
    if not request.args.get("app"):
        flash("No application specified", category="error")
        return redirect("/settings")
    
    # Check application name is valid
    app = request.args.get("app")
    if not is_application_valid(app):
        flash("Application is invalid", category="error")
        return redirect("/settings")

    # Re-install app
    t = Timer(1.0, reinstall_app, [app])
    t.start()

    # Display wait page
    templateData = {
        "title": "myNode Install",
        "header_text": "Installing",
        "subheader_text": "This may take a while...",
        "show_upgrade_log": True,
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/uninstall-app")
def uninstall_app_page():
    check_logged_in()

    # Check application specified
    if not request.args.get("app"):
        flash("No application specified", category="error")
        return redirect("/apps")
    
    # Check application name is valid
    app = request.args.get("app")
    if not is_application_valid(app):
        flash("Application is invalid", category="error")
        return redirect("/apps")

    # Un-install app
    uninstall_app(app)

    flash("Application Uninstalled", category="message")
    return redirect("/apps")

@mynode_settings.route("/settings/toggle-uploader")
def toggle_uploader_page():
    check_logged_in()

    check_and_mark_reboot_action("toggle_uploader")

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

    check_and_mark_reboot_action("toggle_quicksync")

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

@mynode_settings.route("/settings/toggle-testnet")
def toggle_testnet_page():
    check_logged_in()

    check_and_mark_reboot_action("toggle_testnet")

    # Toggle testnet
    toggle_testnet()

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

@mynode_settings.route("/settings/ping")
def ping_page():
    return "alive"

@mynode_settings.route("/settings/toggle-darkmode")
def toggle_darkmode_page():
    check_logged_in()
    toggle_darkmode()
    return redirect("/settings")

@mynode_settings.route("/settings/toggle-darkmode-home")
def toggle_darkmode_page_home():
    check_logged_in()
    toggle_darkmode()
    return redirect("/")

@mynode_settings.route("/settings/set-background", methods=['POST'])
def set_background_page():
    check_logged_in()

    if not request.form.get('background'):
        flash("No background specified", category="error")
        return redirect("/settings")

    bg = request.form.get('background')
    set_background(bg)

    return redirect("/settings")

@mynode_settings.route("/settings/toggle-netdata")
def toggle_netdata_page():
    check_logged_in()

    if is_service_enabled("netdata"):
        disable_service("netdata")
    else:
        enable_service("netdata")
    return redirect("/settings")

@mynode_settings.route("/settings/toggle-check-external-drive")
def toggle_check_external_drive_page():
    check_logged_in()

    if skip_fsck():
        set_skip_fsck(False)
    else:
        set_skip_fsck(True)
    flash("Check External Drive Updated", category="message")
    return redirect("/settings")

@mynode_settings.route("/settings/modify-swap")
def modify_swap_page():
    check_logged_in()

    check_and_mark_reboot_action("modify_swap")

    size = request.args.get('size')
    set_swap_size(size)

    # Trigger reboot
    t = Timer(1.0, reboot_device)
    t.start()

    # Display wait page
    templateData = {
        "title": "myNode Reboot",
        "header_text": "Restarting",
        "subheader_text": "This will take several minutes...",
        "ui_settings": read_ui_settings()
    }
    return render_template('reboot.html', **templateData)

@mynode_settings.route("/settings/clear-oom-error")
def page_clear_oom_error():
    check_logged_in()
    clear_oom_error()
    flash("Warning Cleared", category="message")
    return redirect("/settings")