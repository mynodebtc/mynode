import os
import subprocess

#==================================
# Service Status, Enabled, Logs, etc...
#==================================
def is_service_enabled(service_name):
    cmd = "systemctl is-enabled {}".format(service_name)
    try:
        subprocess.check_call(cmd, shell=True)
        return True
    except:
        return False
    return False

def get_service_status_code(service_name):
    code = os.system("systemctl status {} --no-pager".format(service_name))
    return code

def get_service_status_basic_text(service_name):
    if not is_service_enabled(service_name):
        return "Disabled"

    code = os.system("systemctl status {} --no-pager".format(service_name))
    if code == 0:
        return "Running"
    return "Error"

def get_service_status_color(service_name):
    if not is_service_enabled(service_name):
        return "gray"

    code = os.system("systemctl status {} --no-pager".format(service_name))
    if code == 0:
        return "green"
    return "red"

def get_journalctl_log(service_name):
    try:
        log = subprocess.check_output("journalctl -r --unit={} --no-pager | head -n 200".format(service_name), shell=True).decode("utf8")
    except:
        log = "ERROR"
    return log
