from flask import Blueprint, render_template, session, abort, Markup, request, redirect, url_for, flash
from thread_functions import get_public_ip, find_public_ip
from device_info import is_community_edition, read_ui_settings, get_local_ip
from user_management import check_logged_in, is_admin_password_valid, get_admin_password_error
from systemctl_info import is_service_enabled
from utilities import *
import subprocess
import os
import json


mynode_vpn = Blueprint('mynode_vpn',__name__)

# Helper functions


# Flask Pages
@mynode_vpn.route("/vpn-info")
def page_vpn_info():
    check_logged_in()

    # Check if we are premium
    if is_community_edition():
        return redirect("/")

    vpn_enabled = is_service_enabled("vpn")

    # Check if port is forwarded
    port_forwarded = False
    ip = get_public_ip()
    if vpn_enabled and subprocess.call(["nc", "-v", "-u", "-w", "1", ip, "51194"]) == 0:
        port_forwarded = True

    vpn_file_exists = os.path.isfile("/home/pivpn/ovpns/mynode_vpn.ovpn")

    templateData = {
        "title": "VPN Info",
        "vpn_enabled": vpn_enabled,
        "vpn_file_exists": vpn_file_exists,
        "port_forwarded": port_forwarded,
        "public_ip": ip,
        "local_ip": get_local_ip(),
        "port": "51194",
        "ui_settings": read_ui_settings()
    }
    return render_template('vpn_info.html', **templateData)

@mynode_vpn.route("/regen-vpn", methods=["POST"])
def page_regen_vpn():
    check_logged_in()
    pw = request.form.get('password_regen_ovpn')
    if not is_admin_password_valid(pw):
        flash(get_admin_password_error(), category="error")
        return redirect(url_for(".page_vpn_info"))

    # Regenerating restarts the VPN, so only do it while the VPN is enabled
    if not is_service_enabled("vpn"):
        flash("Enable the VPN before regenerating its files", category="error")
        return redirect(url_for(".page_vpn_info"))

    # Stop
    #os.system("rm /home/pivpn/ovpns/mynode_vpn.ovpn")
    os.system("pivpn -r mynode_vpn")
    os.system("systemctl stop openvpn")
    os.system("systemctl stop vpn")

    # Clean up files
    os.system("rm -rf /mnt/hdd/mynode/vpn/*")

    # Restart
    os.system("systemctl start vpn")

    # Download ovpn
    flash("Regenerating VPN files...", category="message")
    return redirect(url_for(".page_vpn_info"))

@mynode_vpn.route("/mynode.ovpn", methods=["POST"])
def page_download_ovpn():
    check_logged_in()
    pw = request.form.get('password_download_ovpn')
    if not is_admin_password_valid(pw):
        flash(get_admin_password_error(), category="error")
        return redirect(url_for(".page_vpn_info"))

    # Download ovpn
    return download_file(directory="/home/pivpn/ovpns/", filename="mynode_vpn.ovpn")

@mynode_vpn.route("/vpn-info/find-public-ip")
def find_public_ip_page():
    check_logged_in()
    find_public_ip()
    return redirect("/vpn-info")