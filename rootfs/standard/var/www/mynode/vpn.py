from flask import Blueprint, render_template, session, abort, Markup, request, redirect, send_from_directory, url_for, flash
from thread_functions import get_public_ip
from device_info import is_community_edition
from user_management import check_logged_in
import subprocess
import pam
import os


mynode_vpn = Blueprint('mynode_vpn',__name__)

# Helper functions


# Flask Pages
@mynode_vpn.route("/vpn-info")
def page_vpn_info():
    check_logged_in()

    # Check if we are premium
    if is_community_edition():
        return redirect("/")

    # Check if port is forwarded
    port_forwarded = False
    ip = get_public_ip()
    if subprocess.call(["nc", "-v", "-u", "-w", "1", ip, "51194"]) == 0:
        port_forwarded = True

    # Get status
    status = "Setting up..."
    vpn_file_exists = False
    if os.path.isfile("/home/pivpn/ovpns/mynode_vpn.ovpn"):
        vpn_file_exists = True
        status = "Running"

    templateData = {
        "title": "myNode VPN Info",
        "status": status,
        "vpn_file_exists": vpn_file_exists,
        "port_forwarded": port_forwarded,
        "public_ip": ip,
        "port": "51194"
    }
    return render_template('vpn_info.html', **templateData)

@mynode_vpn.route("/regen-vpn", methods=["POST"])
def page_regen_vpn():
    check_logged_in()
    p = pam.pam()
    pw = request.form.get('password_regen_ovpn')
    if pw == None or p.authenticate("admin", pw) == False:
        flash("Invalid Password", category="error")
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
    p = pam.pam()
    pw = request.form.get('password_download_ovpn')
    if pw == None or p.authenticate("admin", pw) == False:
        flash("Invalid Password", category="error")
        return redirect(url_for(".page_vpn_info"))

    # Download ovpn
    return send_from_directory(directory="/home/pivpn/ovpns/", filename="mynode_vpn.ovpn")
