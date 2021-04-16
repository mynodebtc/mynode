import os
import subprocess

service_enabled_cache = {}

#==================================
# Service Status, Enabled, Logs, etc...
#==================================
def clear_service_enabled_cache():
    global service_enabled_cache
    service_enabled_cache = {}

def is_service_enabled(service_name):
    global service_enabled_cache

    if service_name in service_enabled_cache:
        return service_enabled_cache[service_name]

    code = os.system("systemctl is-enabled {} > /dev/null".format(service_name))
    if code == 0:
        service_enabled_cache[service_name] = True
        return True
    service_enabled_cache[service_name] = False
    return False

def get_service_status_code(service_name):
    code = os.system("systemctl status {} --no-pager > /dev/null".format(service_name))
    return code

def get_service_status_basic_text(service_name):
    if not is_service_enabled(service_name):
        return "Disabled"

    code = os.system("systemctl status {} --no-pager  > /dev/null".format(service_name))
    if code == 0:
        return "Running"
    return "Error"

def get_service_status_color(service_name):
    if not is_service_enabled(service_name):
        return "gray"

    code = os.system("systemctl status {} --no-pager > /dev/null".format(service_name))
    if code == 0:
        return "green"
    return "red"

def get_journalctl_log(service_name):
    try:
        log = subprocess.check_output("journalctl -r --unit={} --no-pager | head -n 300".format(service_name), shell=True).decode("utf8")
    except:
        log = "ERROR"
    return log
