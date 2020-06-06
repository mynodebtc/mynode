import os
import subprocess
from config import *
from device_info import is_service_enabled



# Enable disable functions on homepage
def is_lndhub_enabled():
    if os.path.isfile(LNDHUB_ENABLED_FILE):
        return True
    return False

def enable_lndhub():
    os.system("systemctl enable lndhub --no-pager")
    os.system("systemctl start lndhub --no-pager")
    open(LNDHUB_ENABLED_FILE, 'a').close() # touch file

def disable_lndhub():
    if os.path.isfile(LNDHUB_ENABLED_FILE):
        os.remove(LNDHUB_ENABLED_FILE)
    os.system("systemctl stop lndhub --no-pager")
    os.system("systemctl disable lndhub --no-pager")


def is_electrs_enabled():
    if os.path.isfile(ELECTRS_ENABLED_FILE):
        return True
    return False

def enable_electrs():
    os.system("systemctl enable electrs --no-pager")
    os.system("systemctl start electrs --no-pager")
    open(ELECTRS_ENABLED_FILE, 'a').close() # touch file

def disable_electrs():
    if os.path.isfile(ELECTRS_ENABLED_FILE):
        os.remove(ELECTRS_ENABLED_FILE)
    os.system("killall -9 electrs") # Hard kill since we are disabing
    os.system("systemctl stop electrs --no-pager")
    os.system("systemctl disable electrs --no-pager")


def is_rtl_enabled():
    return is_service_enabled("rtl")

def enable_rtl():
    os.system("systemctl enable rtl --no-pager")
    os.system("systemctl start rtl --no-pager")

def disable_rtl():
    os.system("systemctl stop rtl --no-pager")
    os.system("systemctl disable rtl --no-pager")


def is_btcrpcexplorer_enabled():
    if os.path.isfile(BTCRPCEXPLORER_ENABLED_FILE):
        return True
    return False

def enable_btcrpcexplorer():
    os.system("systemctl enable btc_rpc_explorer --no-pager")
    os.system("systemctl start btc_rpc_explorer --no-pager")
    open(BTCRPCEXPLORER_ENABLED_FILE, 'a').close() # touch file

def disable_btcrpcexplorer():
    if os.path.isfile(BTCRPCEXPLORER_ENABLED_FILE):
        os.remove(BTCRPCEXPLORER_ENABLED_FILE)
    #os.system("killall -9 electrs") # Hard kill since we are disabing
    os.system("systemctl stop btc_rpc_explorer --no-pager")
    os.system("systemctl disable btc_rpc_explorer --no-pager")


def is_mempoolspace_enabled():
    return is_service_enabled("mempoolspace")

def enable_mempoolspace():
    os.system("systemctl enable mempoolspace --no-pager")
    os.system("systemctl start mempoolspace --no-pager")
    open(MEMPOOLSPACE_ENABLED_FILE, 'a').close() # touch file

def disable_mempoolspace():
    if os.path.isfile(MEMPOOLSPACE_ENABLED_FILE):
        os.remove(MEMPOOLSPACE_ENABLED_FILE)
    os.system("systemctl stop mempoolspace --no-pager")
    os.system("systemctl disable mempoolspace --no-pager")


def is_btcpayserver_enabled():
    return is_service_enabled("btcpayserver")

def enable_btcpayserver():
    os.system("systemctl enable btcpayserver --no-pager")
    os.system("systemctl start btcpayserver --no-pager")
    open(BTCPAYSERVER_ENABLED_FILE, 'a').close() # touch file

def disable_btcpayserver():
    if os.path.isfile(BTCPAYSERVER_ENABLED_FILE):
        os.remove(BTCPAYSERVER_ENABLED_FILE)
    os.system("systemctl stop btcpayserver --no-pager")
    os.system("systemctl disable btcpayserver --no-pager")


def is_caravan_enabled():
    return is_service_enabled("caravan")

def enable_caravan():
    os.system("systemctl enable caravan --no-pager")
    os.system("systemctl start caravan --no-pager")

def disable_caravan():
    os.system("systemctl stop caravan --no-pager")
    os.system("systemctl disable caravan --no-pager")


def is_vpn_enabled():
    if os.path.isfile(VPN_ENABLED_FILE):
        return True
    return False

def enable_vpn():
    os.system("systemctl enable vpn --no-pager")
    os.system("systemctl start vpn --no-pager")
    open(VPN_ENABLED_FILE, 'a').close() # touch file

def disable_vpn():
    if os.path.isfile(VPN_ENABLED_FILE):
        os.remove(VPN_ENABLED_FILE)
    os.system("systemctl stop vpn --no-pager")
    os.system("systemctl disable vpn --no-pager")
    os.system("systemctl stop openvpn --no-pager")
    os.system("systemctl disable openvpn --no-pager")


def is_netdata_enabled():
    return is_service_enabled("netdata")

def enable_netdata():
    os.system("systemctl enable netdata --no-pager")
    os.system("systemctl start netdata --no-pager")

def disable_netdata():
    os.system("systemctl stop netdata --no-pager")
    os.system("systemctl disable netdata --no-pager")

def is_whirlpool_enabled():
    return is_service_enabled("whirlpool")

def enable_whirlpool():
    os.system("systemctl enable whirlpool --no-pager")
    os.system("systemctl start whirlpool --no-pager")

def disable_whirlpool():
    os.system("systemctl stop whirlpool --no-pager")
    os.system("systemctl disable whirlpool --no-pager")

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

def is_dojo_enabled():
    return is_service_enabled("dojo")

def enable_dojo():
    os.system("systemctl enable dojo --no-pager")
    os.system("systemctl start dojo --no-pager")

def disable_dojo():
    os.system("systemctl stop dojo --no-pager")
    os.system("systemctl disable dojo --no-pager")
