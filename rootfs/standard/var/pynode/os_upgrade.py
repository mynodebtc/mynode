import os
import subprocess
from device_info import get_device_type, get_device_bits, get_debian_version, is_upgrade_running, cleanup_log
from utilities import settings_file_exists, delete_settings_file, get_file_contents, to_string, log_message

# Upgrades the OS one Debian release at a time with mynode_upgrade_os.sh

OS_RELEASE_UPGRADE_UNIT = "mynode-upgrade-os"
OS_RELEASE_UPGRADE_LOG = "/home/admin/upgrade_logs/upgrade_log_os_release.txt"
OS_RELEASE_UPGRADE_ERROR = "os_release_upgrade_error"   # Settings file, set when the last run failed
# Release being upgraded to. mynode_upgrade_os.sh keeps it until the OS packages are upgraded, so it
# is left behind when an upgrade is interrupted (power loss, a crash), and running it again continues.
OS_RELEASE_UPGRADE_TARGET = "/home/bitcoin/.mynode/os_release_upgrade_target"
OS_RELEASE_CODENAME_VERSIONS = {"bullseye": 11, "bookworm": 12}

OS_RELEASE_UPGRADE_DEVICE_TYPES = ["raspi4", "raspi5", "debian"]
# Debian versions mynode_upgrade_os.sh upgrades from, and the release each goes to
OS_RELEASE_UPGRADE_NEXT = {10: (11, "bullseye"), 11: (12, "bookworm")}
LATEST_SUPPORTED_DEBIAN_VERSION = 12

def get_interrupted_os_release_upgrade():
    # Returns (version, codename) of an upgrade that stopped before its OS packages were upgraded, or None
    if is_os_release_upgrade_running():
        return None
    codename = to_string(get_file_contents(OS_RELEASE_UPGRADE_TARGET)).strip()
    if codename not in OS_RELEASE_CODENAME_VERSIONS:
        return None
    return (OS_RELEASE_CODENAME_VERSIONS[codename], codename)

def get_os_release_upgrade_info():
    # What Settings shows for the OS upgrade: {"available": bool, "next_version": int, "next_codename": str,
    # "reason": str}. "reason" says why the upgrade isn't available.
    info = {"available": False, "next_version": None, "next_codename": None, "reason": ""}
    try:
        debian_version = get_debian_version()
    except Exception:
        info["reason"] = "The Debian version of this device could not be read."
        return info
    interrupted = get_interrupted_os_release_upgrade()
    if get_device_type() not in OS_RELEASE_UPGRADE_DEVICE_TYPES or get_device_bits() != 64:
        info["reason"] = "OS upgrades are only supported on 64-bit Raspberry Pi 4, Raspberry Pi 5 and x86 devices."
    elif interrupted:
        # The Debian version can already read as the new release, so continue to the saved one
        info["available"] = True
        info["next_version"], info["next_codename"] = interrupted
    elif debian_version >= LATEST_SUPPORTED_DEBIAN_VERSION:
        info["reason"] = "You are on the latest supported OS (Debian {}).".format(debian_version)
    elif debian_version not in OS_RELEASE_UPGRADE_NEXT:
        info["reason"] = "OS upgrades are not supported from Debian {}.".format(debian_version)
    else:
        info["available"] = True
        info["next_version"], info["next_codename"] = OS_RELEASE_UPGRADE_NEXT[debian_version]
    return info

def is_os_release_upgrade_running():
    # The unit is transient, so it is gone once the script exits
    return subprocess.call(["systemctl", "is-active", "--quiet", OS_RELEASE_UPGRADE_UNIT]) == 0

def start_os_release_upgrade():
    if is_upgrade_running() or is_os_release_upgrade_running():
        return False
    if not get_os_release_upgrade_info()["available"]:
        return False
    delete_settings_file(OS_RELEASE_UPGRADE_ERROR)
    # A systemd unit, so the upgrade keeps running when the web UI restarts
    ret = subprocess.call(["systemd-run", "--unit=" + OS_RELEASE_UPGRADE_UNIT, "--collect",
                           "--description=MyNode OS release upgrade", "/usr/bin/mynode_upgrade_os.sh"])
    if ret != 0:
        log_message("Starting the OS release upgrade failed (exit {})".format(ret))
        return False
    return True

def did_os_release_upgrade_fail():
    return settings_file_exists(OS_RELEASE_UPGRADE_ERROR) and not is_os_release_upgrade_running()

def get_os_release_upgrade_log_tail(lines=40):
    log = to_string(get_file_contents(OS_RELEASE_UPGRADE_LOG))
    if log == "ERROR":
        return ""
    return cleanup_log("\n".join(log.splitlines()[-lines:]))
