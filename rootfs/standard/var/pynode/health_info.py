from device_info import *
from drive_info import *
from systemctl_info import *
from auto_upgrade import get_auto_upgrade_status
import os
import re
import subprocess
import time

# Device health checks for the Status page. Each check returns a dict, or None when it does not apply
# to this device:
#   name     - what is checked
#   status   - "ok", "warning", "error" or "unknown"
#   summary  - one line about the result
#   details  - optional text shown under the summary (preformatted)
#   link     - optional (url, text) for where to fix it
# Dismissing a warning on the home page does not hide it here.

HEALTH_STATUS_COLORS = {"ok": "green", "warning": "yellow", "error": "red", "unknown": "gray"}
HEALTH_STATUS_ORDER = {"error": 0, "warning": 1, "unknown": 2, "ok": 3}

APT_UPDATE_MAX_AGE_DAYS = 7
UNATTENDED_UPGRADES_MAX_AGE_DAYS = 3
DRIVE_USAGE_WARNING = 90
DRIVE_USAGE_ERROR = 95
TEMPERATURE_WARNING = 80


def _check(name, status, summary, details=None, link=None):
    return {"name": name, "status": status, "color": HEALTH_STATUS_COLORS[status],
            "summary": summary, "details": details, "link": link}

def _format_time(t):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(t))

def _days_since(t):
    return (time.time() - t) / 86400

def _usage_percent(usage):
    try:
        return int(re.sub("[^0-9]", "", usage.split(".")[0]))
    except Exception:
        return None


#==================================
# Checks
#==================================
def check_mynode_upgrade():
    current = get_current_version()
    latest = get_latest_version()
    if did_upgrade_fail():
        return _check("MyNode Upgrade", "error", "The last upgrade did not finish. Retry it and check the upgrade log.",
                      link=("/settings#mynode", "Settings"))
    auto_upgrade = get_auto_upgrade_status()
    if auto_upgrade["enabled"] and auto_upgrade["target"] and auto_upgrade["attempts"] > 0 and not auto_upgrade["skipped"]:
        return _check("MyNode Upgrade", "warning",
                      "The automatic upgrade to {} has failed {} time(s).".format(auto_upgrade["target"], auto_upgrade["attempts"]),
                      link=("/settings#mynode", "Settings"))
    if current not in ["0.0", "error"] and latest not in ["0.0", "error"] and current != latest:
        return _check("MyNode Upgrade", "warning", "Version {} is available (running {}).".format(latest, current),
                      link=("/settings#mynode", "Settings"))
    return _check("MyNode Upgrade", "ok", "Running version {}.".format(current))

def check_os_packages_upgrade():
    if did_os_packages_upgrade_fail():
        return _check("OS Package Upgrade", "error", "The last OS package upgrade failed.",
                      details=get_os_packages_upgrade_log_tail(15), link=("/settings#os_packages", "Settings"))
    return None

def check_package_sources():
    error = get_apt_update_error()
    if error is not None:
        return _check("OS Package Sources", "warning",
                      "Some package sources could not be updated during the upgrade on {}. Packages from them stay on older versions.".format(error["time"]),
                      details=error["errors"], link=("/settings#os_packages", "Settings"))
    last_update = get_apt_last_update_time()
    if last_update is None:
        return _check("OS Package Sources", "unknown", "No successful package list update has been recorded.")
    if _days_since(last_update) > APT_UPDATE_MAX_AGE_DAYS and not settings_file_exists("unattended_upgrades_disabled"):
        return _check("OS Package Sources", "warning",
                      "Package lists have not updated without errors since {}.".format(_format_time(last_update)))
    return _check("OS Package Sources", "ok", "Package lists updated {}.".format(_format_time(last_update)))

def check_unattended_upgrades():
    name = "Automatic Security Updates"
    if get_debian_codename() == "buster":
        return _check(name, "unknown", "Debian 10 no longer receives security updates.")
    if settings_file_exists("unattended_upgrades_disabled"):
        return _check(name, "warning", "Turned off.", link=("/settings#os_packages", "Settings"))

    last_run = get_unattended_upgrades_last_run_time()
    errors = get_unattended_upgrades_last_run_errors()
    if errors:
        return _check(name, "warning", "The last run had errors.", details="\n".join(errors[-10:]))
    if last_run is None:
        if get_system_uptime_in_seconds() < 86400:
            return _check(name, "unknown", "Waiting for the first daily run.")
        return _check(name, "warning", "No successful run has been recorded.")
    if _days_since(last_run) > UNATTENDED_UPGRADES_MAX_AGE_DAYS:
        return _check(name, "warning", "Last successful run was {}.".format(_format_time(last_run)))
    return _check(name, "ok", "Last run {}.".format(_format_time(last_run)))

def check_reboot_required():
    newer_kernel = get_newer_installed_kernel()
    if newer_kernel is not None:
        return _check("Reboot Required", "warning",
                      "A newer Linux kernel ({}) is installed. Reboot your device to use it (running {}).".format(newer_kernel, os.uname().release))
    if os.path.isfile("/run/reboot-required"):
        return _check("Reboot Required", "warning", "Updated packages need a reboot to take effect.")
    return _check("Reboot Required", "ok", "No reboot needed.")

def check_kernel_security():
    kernel_version = get_kernel_version_string()
    if is_kernel_affected_by_cve_2026_98432(get_kernel_version()):
        fixed = get_cve_2026_98432_fixed_kernel_version()
        summary = "Linux {} is affected by CVE-2026-98432.".format(kernel_version)
        if fixed:
            summary += " Fixed in {} and newer.".format(fixed)
        if is_kernel_cve_mitigated_device():
            summary += " MyNode mitigations are in place on this device."
        return _check("Kernel Security", "error", summary, link=("/settings#os_packages", "Settings"))
    return _check("Kernel Security", "ok", "Linux {} has no known issues tracked by MyNode.".format(kernel_version))

def check_power():
    data = get_throttled_data()
    if data["RAW_DATA"] == "MISSING":
        return None
    if data["UNDERVOLTED"]:
        return _check("Power", "error", "The device is undervolted right now. Your power supply may be failing or too weak.")
    problems = []
    if data["HAS_UNDERVOLTED"]:
        problems.append("undervolted")
    if data["HAS_THROTTLED"] or data["THROTTLED"]:
        problems.append("CPU throttled")
    if data["HAS_CAPPED"] or data["CAPPED"]:
        problems.append("CPU capped")
    if data["HAS_SOFT_TEMPLIMIT"] or data["SOFT_TEMPLIMIT"]:
        problems.append("hit the soft temperature limit")
    if problems:
        return _check("Power", "warning", "Since the last reboot the device has: {}.".format(", ".join(problems)))
    return _check("Power", "ok", "No undervoltage or throttling.")

def check_temperature():
    temp = get_device_temp()
    try:
        temp_value = float(temp)
    except (TypeError, ValueError):
        return None
    if temp_value >= TEMPERATURE_WARNING:
        return _check("Temperature", "warning", "{} °C. The device may slow down to cool off.".format(temp))
    return _check("Temperature", "ok", "{} °C".format(temp))

def check_memory():
    if has_oom_error():
        return _check("Memory", "warning", "The device ran low on memory and a process was restarted. You may want to disable some apps.",
                      details=get_oom_error_info(), link=("/settings/clear-oom-error", "Clear"))
    return _check("Memory", "ok", "RAM usage {}".format(get_ram_usage()))

def check_failed_services():
    failed = get_failed_services()
    if failed:
        return _check("Services", "warning", "{} service(s) crashed or failed to start: {}. Their logs are in Service Status below.".format(len(failed), ", ".join(failed)))
    return _check("Services", "ok", "No failed services.")

def check_data_drive():
    name = "Data Drive"
    if has_fsck_error():
        return _check(name, "error", "The filesystem check at startup found a problem.", details=get_fsck_results())
    if has_usb_error():
        return _check(name, "error", "Several read/write errors were detected. The USB adapter or cable may be failing.",
                      link=("/settings/clear-usb-error", "Clear"))
    usage = get_data_drive_usage()
    percent = _usage_percent(usage)
    if percent is not None and percent >= DRIVE_USAGE_ERROR:
        return _check(name, "error", "{} full. Free space is running very low.".format(usage), link=("/settings#clone_tool", "Clone Tool"))
    if percent is not None and percent >= DRIVE_USAGE_WARNING:
        return _check(name, "warning", "{} full.".format(usage))
    return _check(name, "ok", "{} used".format(usage))

def check_os_drive():
    name = "OS Drive"
    if has_sd_rw_error():
        return _check(name, "error", "The OS drive was mounted read-only at startup, which can mean filesystem errors.")
    usage = get_os_drive_usage()
    percent = _usage_percent(usage)
    if percent is not None and percent >= DRIVE_USAGE_ERROR:
        return _check(name, "error", "{} full. Free space is running very low.".format(usage))
    if percent is not None and percent >= DRIVE_USAGE_WARNING:
        return _check(name, "warning", "{} full.".format(usage))
    return _check(name, "ok", "{} used".format(usage))

def check_clock():
    try:
        synced = to_string(subprocess.check_output(["timedatectl", "show", "-p", "NTPSynchronized", "--value"],
                                                   stderr=subprocess.DEVNULL, timeout=5)).strip()
    except Exception:
        return None
    if synced == "yes":
        return _check("Clock", "ok", "Synchronized with network time.")
    if synced == "no":
        return _check("Clock", "warning", "Not synchronized with network time. A wrong clock can break Tor and HTTPS.")
    return None

def check_server_connection():
    if has_checkin_error():
        return _check("MyNode Server", "warning", "Could not contact mynodebtc.com via Tor. Checking for new versions may not work. This may be temporary.")
    return _check("MyNode Server", "ok", "Connected.")

def check_operating_system():
    debian_version = get_debian_version()
    if debian_version < 12:
        return _check("Operating System", "error", "Debian {} is no longer supported. Reflash your OS drive with the latest MyNode image.".format(debian_version),
                      link=("https://mynodebtc.com/download", "Download"))
    if get_device_bits() == 32:
        return _check("Operating System", "warning", "32-bit image. Some apps can no longer be updated. Reflash your OS drive with the 64-bit image.",
                      link=("https://mynodebtc.com/download", "Download"))
    return _check("Operating System", "ok", "Debian {} ({}), {}".format(debian_version, get_debian_codename(), get_device_arch()))

def check_nodejs():
    version = get_node_version()
    if version == "":
        return None
    warning = get_node_version_warning()
    if warning == "reflash":
        return _check("NodeJS", "error", "NodeJS {} no longer receives security fixes. Reflash your OS drive to get a supported version.".format(version))
    if warning == "upgrade":
        return _check("NodeJS", "error", "NodeJS {} has known security issues. Upgrade MyNode to install a newer version.".format(version),
                      link=("/settings#mynode", "Settings"))
    return _check("NodeJS", "ok", "Version {}".format(version))

def check_tor_version():
    try:
        version = get_tor_version()
    except Exception:
        return None
    if version.startswith("0.4.8"):
        return _check("Tor", "warning", "Tor {} is out of date. Reflash your OS drive to get a newer version.".format(version))
    return _check("Tor", "ok", "Version {}".format(version))

HEALTH_CHECKS = [
    check_mynode_upgrade,
    check_os_packages_upgrade,
    check_package_sources,
    check_unattended_upgrades,
    check_reboot_required,
    check_kernel_security,
    check_failed_services,
    check_power,
    check_temperature,
    check_memory,
    check_data_drive,
    check_os_drive,
    check_clock,
    check_server_connection,
    check_operating_system,
    check_nodejs,
    check_tor_version,
]

def get_health_checks():
    # Problems first, then the rest in the order above
    results = []
    for check in HEALTH_CHECKS:
        try:
            result = check()
        except Exception as e:
            log_message("Health check {} failed: {}".format(check.__name__, str(e)))
            result = _check(check.__name__.replace("check_", "").replace("_", " ").title(), "unknown", "Could not be checked.")
        if result is not None:
            results.append(result)
    return sorted(results, key=lambda r: HEALTH_STATUS_ORDER[r["status"]])

def get_health_summary(checks):
    errors = len([c for c in checks if c["status"] == "error"])
    warnings = len([c for c in checks if c["status"] == "warning"])
    if errors:
        status = "error"
    elif warnings:
        status = "warning"
    else:
        status = "ok"
    parts = []
    if errors:
        parts.append("{} error{}".format(errors, "" if errors == 1 else "s"))
    if warnings:
        parts.append("{} warning{}".format(warnings, "" if warnings == 1 else "s"))
    text = ", ".join(parts) if parts else "No problems found"
    return {"status": status, "color": HEALTH_STATUS_COLORS[status], "text": text}
