import os
import subprocess
import threading
import time
from utilities import *

service_enabled_cache = {}

# Active state of every loaded service, from one "systemctl list-units" call (about 10 ms). The home
# page asks for the status of every app at once; this replaces a "systemctl status" per app.
# Units that are not loaded (not installed, or disabled and stopped) are missing, which reads as
# not running. Only real unit names are found, not aliases such as "sshd" for "ssh".
SERVICE_STATUS_MAX_AGE = 10
SERVICE_ACTIVE_STATES = ["active", "reloading", "refreshing"]
service_status_cache = {}
service_status_cache_time = 0
service_status_cache_lock = threading.Lock()

#==================================
# Service Status, Enabled, Logs, etc...
#==================================
def clear_service_enabled_cache():
    global service_enabled_cache
    service_enabled_cache = {}

def is_service_enabled(service_name, force_refresh=False):
    global service_enabled_cache

    # Look up once - another thread can replace the cache with an empty one at any time
    cached = service_enabled_cache.get(service_name)
    if cached is not None and force_refresh == False:
        return cached

    code = os.system("systemctl is-enabled {} > /dev/null 2>&1".format(service_name))
    if code == 0:
        service_enabled_cache[service_name] = True
        return True
    service_enabled_cache[service_name] = False
    return False

def is_service_active(service_name):
    # Running right now, whether or not it is enabled at boot
    return os.system("systemctl is-active {} > /dev/null 2>&1".format(service_name)) == 0

def clear_service_status_cache():
    # Call after starting, stopping, enabling or disabling a service so the next status is current
    global service_status_cache_time
    # The lock waits out a refresh already running, which may have read the old state
    with service_status_cache_lock:
        service_status_cache_time = 0

def update_service_status_cache():
    global service_status_cache
    global service_status_cache_time
    try:
        output = to_string(subprocess.check_output(["systemctl", "list-units", "--all", "--type=service",
                                                    "--plain", "--no-legend", "--no-pager"], timeout=10))
    except Exception as e:
        log_message("update_service_status_cache: systemctl list-units failed: {}".format(str(e)))
        return False

    # Columns are UNIT LOAD ACTIVE SUB DESCRIPTION
    states = {}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[0].endswith(".service"):
            states[fields[0][:-len(".service")]] = fields[2]
    service_status_cache = states
    service_status_cache_time = time.time()
    return True

def refresh_service_status_cache():
    # Background refresh, so the cache stays warm while no one has the UI open
    with service_status_cache_lock:
        update_service_status_cache()

def get_service_status_code(service_name):
    # 0 when running, like the exit code of "systemctl status"
    with service_status_cache_lock:
        if time.time() - service_status_cache_time > SERVICE_STATUS_MAX_AGE:
            if not update_service_status_cache():
                return os.system("systemctl status {} --no-pager > /dev/null 2>&1".format(service_name))
        state = service_status_cache.get(service_name)
    if state in SERVICE_ACTIVE_STATES:
        return 0
    return 3

# Automatic restarts before a service that keeps running counts as crashing. Most MyNode services
# restart 30-60 seconds after a crash, which never reaches systemd's start limit (5 starts in 10
# seconds), so a crashing service is rarely marked failed. It restarts forever instead.
SERVICE_CRASH_RESTARTS = 3
# ...but only while it is still restarting. NRestarts is not reset until the service is started by
# hand, and services that wait on bitcoind or the data drive often restart several times at boot and
# then run fine for days. A crashing service starts again within RestartSec (at most 120 seconds).
SERVICE_CRASH_RECENT_SECONDS = 15 * 60

def parse_service_problems(output, now_monotonic_usec):
    # Parses "systemctl show --property=Id,ActiveState,NRestarts,ExecMainStartTimestampMonotonic"
    # output for several units (blocks of KEY=VALUE lines separated by blank lines)
    problems = []
    for block in output.strip().split("\n\n"):
        props = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        unit = props.get("Id", "")
        if not unit.endswith(".service"):
            continue
        try:
            restarts = int(props.get("NRestarts", "0"))
        except ValueError:
            restarts = 0
        try:
            last_start = int(props.get("ExecMainStartTimestampMonotonic", "0"))
        except ValueError:
            last_start = 0
        started_recently = last_start > 0 and now_monotonic_usec - last_start < SERVICE_CRASH_RECENT_SECONDS * 1000000
        if props.get("ActiveState") == "failed":
            problems.append({"name": unit[:-len(".service")], "state": "failed", "restarts": restarts})
        elif restarts >= SERVICE_CRASH_RESTARTS and started_recently:
            problems.append({"name": unit[:-len(".service")], "state": "restarting", "restarts": restarts})
    return sorted(problems, key=lambda p: p["name"])

def get_service_problems():
    # Services that failed, or that crashed and were restarted automatically SERVICE_CRASH_RESTARTS
    # or more times since they were last started by hand (or since boot), most recently in the last
    # SERVICE_CRASH_RECENT_SECONDS
    try:
        units = to_string(subprocess.check_output(["systemctl", "list-units", "--all", "--type=service",
                                                   "--plain", "--no-legend", "--no-pager"], timeout=10))
        names = [line.split()[0] for line in units.splitlines() if line.split() and line.split()[0].endswith(".service")]
        if len(names) == 0:
            return []
        output = to_string(subprocess.check_output(["systemctl", "show",
                                                    "--property=Id,ActiveState,NRestarts,ExecMainStartTimestampMonotonic",
                                                    "--no-pager"] + names, timeout=10))
    except Exception as e:
        log_message("get_service_problems: systemctl show failed: {}".format(str(e)))
        return []
    # systemd's monotonic timestamps use the same clock as time.monotonic() (CLOCK_MONOTONIC)
    return parse_service_problems(output, int(time.monotonic() * 1000000))

def get_service_status_basic_text(service_name):
    if not is_service_enabled(service_name):
        return "Disabled"

    if get_service_status_code(service_name) == 0:
        return "Running"
    return "Error"

def get_service_status_color(service_name):
    if not is_service_enabled(service_name):
        return "gray"

    if get_service_status_code(service_name) == 0:
        return "green"
    return "red"

def get_journalctl_log(service_name):
    try:
        log = to_string(subprocess.check_output("journalctl -r --unit={} --no-pager | head -n 300".format(service_name), shell=True).decode("utf8"))
    except:
        log = "ERROR"
    return log
