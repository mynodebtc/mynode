import os
import subprocess
from werkzeug.routing import RequestRedirect
from config import *
from systemctl_info import *

# Generic Enable / Disable Function
def enable_service(short_name):
    os.system("systemctl enable {} --no-pager".format(short_name))
    os.system("systemctl start {} --no-pager".format(short_name))
    open("/mnt/hdd/mynode/settings/{}_enabled".format(short_name), 'a').close() # touch file
    clear_service_enabled_cache()
    enable_actions(short_name)

def disable_service(short_name):
    enabled_file = "/mnt/hdd/mynode/settings/{}_enabled".format(short_name)
    if os.path.isfile(enabled_file):
        os.remove(enabled_file)
    disable_actions(short_name)
    os.system("systemctl stop {} --no-pager".format(short_name))
    os.system("systemctl disable {} --no-pager".format(short_name))
    clear_service_enabled_cache()

# Functions to handle special enable/disable cases
def enable_actions(short_name):
    pass

def disable_actions(short_name):
    if short_name == "electrs":
        # Hard kill since we are disabling
        os.system("killall -9 electrs")
    if short_name == "vpn":
        # Disable OpenVPN as well
        os.system("systemctl stop openvpn --no-pager")
        os.system("systemctl disable openvpn --no-pager")

# Function to restart service
def restart_service(short_name):
    os.system("systemctl restart {} --no-pager".format(short_name))

