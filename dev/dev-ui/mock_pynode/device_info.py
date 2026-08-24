"""Mock shim for pynode/device_info.py.

Overrides only the functions that touch hardware or would take the container
down (uptime, serial/type/arch, temperature, reboot/shutdown/upgrade). The
state machine (get_mynode_status, STATE_* constants), marker-file helpers and
warning logic all stay real - they are driven by the fixture filesystem and
the dev panel."""
import glob
import os
import threading
import time

from _mockutil import load_real, export, fixture

_real = load_real("device_info")

_dev = fixture("device.json")

FAKE_BOOT_TIME_FILE = "/tmp/fake_boot_time"


def _get_fake_boot_time():
    try:
        with open(FAKE_BOOT_TIME_FILE) as f:
            return float(f.read().strip())
    except Exception:
        return time.time() - 7200


def _set_fake_boot_time(value):
    with open(FAKE_BOOT_TIME_FILE, "w") as f:
        f.write(str(value))


def get_system_uptime_in_seconds():
    return int(time.time() - _get_fake_boot_time())


def get_system_uptime():
    s = get_system_uptime_in_seconds()
    return "{} days {} hour(s) {} minute(s)".format(s // 86400, (s % 86400) // 3600, (s % 3600) // 60)


def get_device_serial():
    return _dev["serial"]


def get_device_type():
    return _dev["device_type"]


def get_device_arch():
    return _dev["arch"]


def get_device_ram():
    return _dev["ram"]


def get_debian_codename():
    return _dev["debian_codename"]


def get_debian_version():
    return int(_dev["debian_version"])


def get_tor_version():
    return _dev["tor_version"]


def get_device_temp():
    return _dev["temp"]


def get_local_ip():
    return _dev["local_ip"]


def get_quicksync_log():
    return "(mock) QuickSync is disabled in the UI dev container"


def get_firewall_rules():
    return ("Status: active (mocked)\n\n"
            "To                         Action      From\n"
            "--                         ------      ----\n"
            "22/tcp                     ALLOW       Anywhere\n"
            "80/tcp                     ALLOW       Anywhere\n"
            "443/tcp                    ALLOW       Anywhere\n"
            "8333/tcp                   ALLOW       Anywhere\n")


#==================================
# Simulated power cycle
#==================================
# The real reboot page (reboot.html) polls /api/ping and redirects home once
# it sees uptime DECREASE. Resetting the fake boot time reproduces the whole
# reboot UX without touching the container.

# Uptime the device "comes back" with after a simulated reboot. It must be
# LESS than the pre-reboot uptime so reboot.html (which redirects home when it
# sees uptime decrease) detects the reboot. At 170s we land just under the
# homepage's "just booted" gate (uptime < 180 -> "Starting..." page), so the
# real Starting screen shows briefly (~10s) before the page auto-refreshes into
# the stable homepage.
POST_REBOOT_UPTIME = 170


def _simulate_power_cycle(downtime=6):
    def _do():
        _real.touch("/tmp/shutting_down")
        with open("/tmp/.mynode_status", "w") as f:
            f.write("shutting_down")
        time.sleep(downtime)
        # Clear one-shot markers exactly like a real reboot would
        for marker in glob.glob("/tmp/mark_reboot___*"):
            try:
                os.remove(marker)
            except OSError:
                pass
        for f in ["/tmp/upgrade_started", "/tmp/shutting_down", "/tmp/skip_base_upgrades"]:
            if os.path.exists(f):
                os.remove(f)
        _set_fake_boot_time(time.time() - POST_REBOOT_UPTIME)
        with open("/tmp/.mynode_status", "w") as f:
            f.write("stable")

    threading.Thread(target=_do, daemon=True).start()


def reboot_device():
    _real.log_message("[mock] reboot_device: simulating reboot")
    _simulate_power_cycle(downtime=6)


def shutdown_device():
    # A real shutdown never comes back; for dev convenience the mock "powers
    # on" again after a longer pause.
    _real.log_message("[mock] shutdown_device: simulating shutdown (auto power-on in 15s)")
    _simulate_power_cycle(downtime=15)


def factory_reset():
    _real.log_message("[mock] factory_reset: no-op + simulated reboot")
    reboot_device()


def reset_docker():
    _real.log_message("[mock] reset_docker: no-op + simulated reboot")
    reboot_device()


def _write_fake_upgrade_log(action, extra_lines=None):
    os.makedirs("/home/admin/upgrade_logs", exist_ok=True)
    lines = [
        "===== {} started (MOCKED - UI dev container) =====".format(action),
        "Stopping services...",
        "Downloading files... done",
        "Installing... done",
    ] + (extra_lines or []) + [
        "===== {} complete - rebooting =====".format(action),
    ]
    latest = "/home/admin/upgrade_logs/upgrade_log_latest.txt"
    with open(latest, "w") as f:
        pass
    for line in lines:
        with open(latest, "a") as f:
            f.write(line + "\n")
        time.sleep(0.7)


def upgrade_device():
    if not _real.is_upgrade_running():
        _real.mark_upgrade_started()
        _write_fake_upgrade_log("Upgrade to {}".format(_real.get_latest_version()))
        time.sleep(1)
        reboot_device()


def upgrade_device_beta():
    if not _real.is_upgrade_running():
        _real.mark_upgrade_started()
        _write_fake_upgrade_log("Beta upgrade")
        time.sleep(1)
        reboot_device()


def install_custom_bitcoin_version(version):
    _real.mark_upgrade_started()
    _write_fake_upgrade_log("Custom bitcoin install ({})".format(version))
    time.sleep(1)
    reboot_device()


# Patch overrides into the real namespace so intra-module calls and
# star-import copies both resolve to the mocks.
_real.get_system_uptime_in_seconds = get_system_uptime_in_seconds
_real.get_system_uptime = get_system_uptime
_real.get_device_serial = get_device_serial
_real.get_device_type = get_device_type
_real.get_device_arch = get_device_arch
_real.get_device_ram = get_device_ram
_real.get_debian_codename = get_debian_codename
_real.get_debian_version = get_debian_version
_real.get_tor_version = get_tor_version
_real.get_device_temp = get_device_temp
_real.get_local_ip = get_local_ip
_real.get_quicksync_log = get_quicksync_log
_real.get_firewall_rules = get_firewall_rules
_real.reboot_device = reboot_device
_real.shutdown_device = shutdown_device
_real.factory_reset = factory_reset
_real.reset_docker = reset_docker
_real.upgrade_device = upgrade_device
_real.upgrade_device_beta = upgrade_device_beta
_real.install_custom_bitcoin_version = install_custom_bitcoin_version

export(globals(), _real)
