import subprocess
from utilities import *

service_enabled_cache = {}

#==================================
# Service Status, Enabled, Logs, etc...
#==================================
def clear_service_enabled_cache():
    global service_enabled_cache
    service_enabled_cache = {}

def run_systemctl_status_command(command, service_name):
    return subprocess.run(
        ["systemctl", command, "--no-pager", "--", str(service_name)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode

def is_service_enabled(service_name, force_refresh=False):
    global service_enabled_cache

    if service_name in service_enabled_cache and force_refresh == False:
        return service_enabled_cache[service_name]

    code = subprocess.run(
        ["systemctl", "is-enabled", "--", str(service_name)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode
    if code == 0:
        service_enabled_cache[service_name] = True
        return True
    service_enabled_cache[service_name] = False
    return False

def get_service_status_code(service_name):
    return run_systemctl_status_command("status", service_name)

def get_service_status_basic_text(service_name):
    if not is_service_enabled(service_name):
        return "Disabled"

    code = run_systemctl_status_command("status", service_name)
    if code == 0:
        return "Running"
    return "Error"

def get_service_status_color(service_name):
    if not is_service_enabled(service_name):
        return "gray"

    code = run_systemctl_status_command("status", service_name)
    if code == 0:
        return "green"
    return "red"

def get_journalctl_log(service_name):
    try:
        log = to_string(
            subprocess.check_output(
                ["journalctl", "-r", "-n", "300", f"--unit={service_name}", "--no-pager"]
            ).decode("utf8")
        )
    except:
        log = "ERROR"
    return log
