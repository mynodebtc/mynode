"""Mock of pynode/systemctl_info.py - the fully centralized service-status
module. Backed by /tmp/mock_services/<name> state files (running | stopped |
failed | disabled) which the fake `systemctl` binary manipulates, so raw
`os.system("systemctl ...")` calls elsewhere in the real code stay consistent
with this python view.

This mock is standalone (it does not exec the real module) because every
function needs replacing and it avoids a shell fork per app tile on the
homepage. The import surface mirrors the real module."""
import os
import subprocess
import time
from utilities import *

MOCK_SERVICES_DIR = "/tmp/mock_services"

service_enabled_cache = {}


def _service_state(service_name):
    try:
        with open(os.path.join(MOCK_SERVICES_DIR, service_name)) as f:
            return f.read().strip()
    except Exception:
        return "disabled"


def clear_service_enabled_cache():
    global service_enabled_cache
    service_enabled_cache = {}


def is_service_enabled(service_name, force_refresh=False):
    return _service_state(service_name) != "disabled"


def is_service_active(service_name):
    return _service_state(service_name) == "running"


# The real module caches "systemctl list-units"; the state files need no cache
def clear_service_status_cache():
    pass


def update_service_status_cache():
    return True


def refresh_service_status_cache():
    pass


def get_service_status_code(service_name):
    return 0 if _service_state(service_name) == "running" else 3


def get_service_problems():
    try:
        names = os.listdir(MOCK_SERVICES_DIR)
    except Exception:
        return []
    return [{"name": n, "state": "failed", "restarts": 0} for n in sorted(names) if _service_state(n) == "failed"]


def get_service_status_basic_text(service_name):
    state = _service_state(service_name)
    if state == "disabled":
        return "Disabled"
    if state == "running":
        return "Running"
    return "Error"


def get_service_status_color(service_name):
    state = _service_state(service_name)
    if state == "disabled":
        return "gray"
    if state == "running":
        return "green"
    return "red"


def get_journalctl_log(service_name):
    # The fake journalctl binary produces service-aware canned output; going
    # through it keeps python and shell views identical.
    try:
        log = to_string(subprocess.check_output(
            "journalctl -r --unit={} --no-pager | head -n 300".format(service_name),
            shell=True).decode("utf8"))
    except Exception:
        log = "ERROR"
    return log
