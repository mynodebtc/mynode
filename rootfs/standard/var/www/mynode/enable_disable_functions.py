import os
import subprocess
from config import *
from systemctl_info import *

# Generic Enable / Disable Function
def enable_service(short_name):
    enable_actions(short_name)
    os.system("systemctl enable {} --no-pager".format(short_name))
    os.system("systemctl start {} --no-pager".format(short_name))
    open("/mnt/hdd/mynode/settings/{}_enabled".format(short_name), 'a').close() # touch file
    clear_service_enabled_cache()

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




# Dojo install / uninstall functions.... future work to abstract this
def is_dojo_installed():
    return os.path.isfile(DOJO_INSTALL_FILE)

def install_dojo():
    os.system("touch " + DOJO_INSTALL_FILE)
    os.system("sync")

def uninstall_dojo():
    os.system("rm -f " + DOJO_INSTALL_FILE)
    os.system("rf -f /mnt/hdd/mynode/settings/dojo_url")
    disable_dojo()
    os.system("sync")

