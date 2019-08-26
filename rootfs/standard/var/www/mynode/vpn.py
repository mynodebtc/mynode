from flask import Blueprint, render_template, session, abort, Markup, request, redirect, send_from_directory, url_for
from thread_functions import get_public_ip
import subprocess
import pam
import os


mynode_vpn = Blueprint('mynode_vpn',__name__)

# Helper functions


# Flask Pages
@mynode_vpn.route("/vpn-info")
def page_vpn_info():

    message = ""
    if request.args.get('error_message'):
        message = Markup("<div class='error_message'>"+request.args.get('error_message')+"</div>")
    if request.args.get('success_message'):
        message = Markup("<div class='success_message'>"+request.args.get('success_message')+"</div>")

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
        "message": message,
        "vpn_file_exists": vpn_file_exists,
        "port_forwarded": port_forwarded,
        "public_ip": ip,
        "port": "51194"
    }
    return render_template('vpn_info.html', **templateData)

@mynode_vpn.route("/regen-vpn", methods=["POST"])
def page_regen_vpn():
    p = pam.pam()
    pw = request.form.get('password_regen_ovpn')
    if pw == None or p.authenticate("admin", pw) == False:
        return redirect(url_for(".page_vpn_info", error_message="Invalid Password"))

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
    return redirect(url_for(".page_vpn_info", success_message="Regenerating VPN files..."))

@mynode_vpn.route("/mynode.ovpn", methods=["POST"])
def page_download_ovpn():
    p = pam.pam()
    pw = request.form.get('password_download_ovpn')
    if pw == None or p.authenticate("admin", pw) == False:
        return redirect(url_for(".page_vpn_info", error_message="Invalid Password"))

    # Download ovpn
    return send_from_directory(directory="/home/pivpn/ovpns/", filename="mynode_vpn.ovpn")
