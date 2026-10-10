from utilities import *
from device_info import *
from drive_info import *
import glob
import json
import os
import re
import subprocess
import time

#==================================
# Automatic Upgrades
#==================================
# A new MyNode version is installed automatically 7 days after this device first sees it (the
# version check is already spread over several days), between 3 and 5 AM local time. /usr/bin/mynode_auto_upgrade.py runs this hourly.

AUTO_UPGRADE_STATE_FILE = "/mnt/hdd/mynode/settings/auto_upgrade.json"
AUTO_UPGRADE_DELAY_DAYS = 7
AUTO_UPGRADE_WINDOW_START_HOUR = 3
AUTO_UPGRADE_WINDOW_END_HOUR = 5
AUTO_UPGRADE_NIGHTLY_ATTEMPTS = 3   # Failed installs retried on consecutive nights...
AUTO_UPGRADE_WEEKLY_RETRY_DAYS = 7  # ...then once a week

# Results of mynode_upgrade.sh that leave the device unchanged
UPGRADE_EXIT_NOT_VERIFIED = 1
UPGRADE_EXIT_WRONG_VERSION = 3

DAY = 24 * 60 * 60

def default_auto_upgrade_state():
    return {
        "target": None,          # Newer version waiting to be installed
        "first_seen": None,      # When this device first saw target
        "attempts": 0,           # Failed installs of target (not counting failed downloads)
        "last_attempt": None,    # Any attempt, limits attempts to one per night
        "last_failure": None,    # Last failed install, spaces out weekly retries
        "stage": None,           # "running" while an upgrade is in progress
        "from_version": None,    # Version installed when the running upgrade started
        "skipped": None,         # Version the owner chose to skip
        "last_result": None,
    }

def is_auto_upgrade_enabled():
    return settings_file_exists("auto_upgrade_enabled")

def set_auto_upgrade_enabled(enabled):
    if enabled:
        create_settings_file("auto_upgrade_enabled")
    else:
        delete_settings_file("auto_upgrade_enabled")

def can_auto_upgrade():
    # The release download needs a product key
    return has_product_key() and not skipped_product_key()

def get_auto_upgrade_state():
    state = default_auto_upgrade_state()
    try:
        with open(AUTO_UPGRADE_STATE_FILE, "r") as f:
            saved = json.load(f)
        if isinstance(saved, dict):
            state.update(saved)
    except Exception:
        pass
    return state

def save_auto_upgrade_state(state):
    tmp = AUTO_UPGRADE_STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=4, sort_keys=True)
    os.replace(tmp, AUTO_UPGRADE_STATE_FILE)
    os.system("sync")

def parse_version(version):
    # "0.3.49" -> (0, 3, 49), "0.3.48-2" -> (0, 3, 48, 2); anything else -> None
    if not isinstance(version, str) or not re.match(r"^[0-9]+([.-][0-9]+)*$", version):
        return None
    return tuple(int(x) for x in re.split(r"[.-]", version))

def is_newer_version(version, than):
    a = parse_version(version)
    b = parse_version(than)
    return a is not None and b is not None and a > b

def read_latest_version_file():
    # Unlike get_latest_version(), returns None when the last check failed (a failed wget leaves
    # the file empty) instead of the current version, so a failed check never looks like a
    # pulled release
    try:
        with open("/usr/share/mynode/latest_version", "r") as f:
            latest = f.read().strip()
        if parse_version(latest) is not None:
            return latest
    except Exception:
        pass
    return None

#----------------------------------
# Decisions (no side effects)
#----------------------------------
def update_auto_upgrade_target(state, current, latest, now):
    # Track the version waiting to be installed. Returns True if the state changed.
    if parse_version(current) is None or latest is None:
        return False

    if not is_newer_version(latest, current):
        # Installed already (manually or automatically), or the release was pulled
        if state["target"] is not None:
            state.update(target=None, first_seen=None, attempts=0,
                         last_attempt=None, last_failure=None)
            return True
        return False

    if latest != state["target"]:
        # A new release, or a newer one replacing the version that was waiting
        state.update(target=latest, first_seen=now, attempts=0, last_attempt=None, last_failure=None)
        return True

    if state["first_seen"] is None or state["first_seen"] > now + DAY:
        # Saved while the clock was wrong
        state["first_seen"] = now
        return True
    return False

def get_auto_upgrade_scheduled_time(state):
    if state["target"] is None or state["first_seen"] is None:
        return None
    return state["first_seen"] + AUTO_UPGRADE_DELAY_DAYS * DAY

def get_next_retry_time(state):
    # Earliest time the retry schedule allows another attempt
    times = []
    if state["last_attempt"] is not None:
        # One attempt per night
        times.append(state["last_attempt"] + 12 * 60 * 60)
    if state["attempts"] >= AUTO_UPGRADE_NIGHTLY_ATTEMPTS and state["last_failure"] is not None:
        # Weekly, with slack so the retry still lands in the window a week later
        times.append(state["last_failure"] + AUTO_UPGRADE_WEEKLY_RETRY_DAYS * DAY - 6 * 60 * 60)
    return max(times) if times else None

def is_in_auto_upgrade_window(local_hour):
    return AUTO_UPGRADE_WINDOW_START_HOUR <= local_hour < AUTO_UPGRADE_WINDOW_END_HOUR

def get_auto_upgrade_wait_reason(state, now, local_hour):
    # None if target should be installed now, otherwise why not
    if state["target"] is None:
        return "no newer version"
    if state["skipped"] == state["target"]:
        return "v{} skipped by the owner".format(state["target"])
    scheduled = get_auto_upgrade_scheduled_time(state)
    if scheduled is None or now < scheduled:
        return "v{} waiting until {}".format(state["target"], format_auto_upgrade_time(scheduled))
    retry = get_next_retry_time(state)
    if retry is not None and now < retry:
        return "next attempt not before {}".format(format_auto_upgrade_time(retry))
    if not is_in_auto_upgrade_window(local_hour):
        return "outside the {}:00-{}:00 window".format(AUTO_UPGRADE_WINDOW_START_HOUR, AUTO_UPGRADE_WINDOW_END_HOUR)
    return None

def reconcile_interrupted_upgrade(state, current, upgrade_error, now):
    # An upgrade that was still "running" when the device restarted (power cut, crash).
    # Returns True if the state changed.
    if state["stage"] != "running":
        return False
    target = state["target"]
    if target is not None and current == target and not upgrade_error:
        state.update(last_result={"result": "ok", "from": state["from_version"], "to": target, "time": now},
                     target=None, first_seen=None, attempts=0,
                     last_attempt=None, last_failure=None)
    elif not upgrade_error and current == state["from_version"]:
        # Stopped before installing anything
        state["last_result"] = {"result": "not_installed", "to": target, "time": now,
                                "detail": "Interrupted before installing"}
    else:
        state["attempts"] += 1
        state["last_failure"] = now
        state["last_result"] = {"result": "failed", "to": target, "time": now,
                                "detail": "Interrupted while installing"}
    state["stage"] = None
    state["from_version"] = None
    return True

def format_auto_upgrade_time(t):
    if t is None:
        return "unknown"
    # The timezone can change after this process started (Settings, or startup re-applying it)
    time.tzset()
    return time.strftime("%Y-%m-%d %H:%M %Z", time.localtime(t))

#----------------------------------
# Device checks
#----------------------------------
def is_clock_synchronized():
    try:
        out = subprocess.check_output(["timedatectl", "show", "-p", "NTPSynchronized", "--value"],
                                      stderr=subprocess.DEVNULL)
        return to_string(out).strip() == "yes"
    except Exception:
        return False

def has_recent_reboot_action():
    # Markers left by check_and_mark_reboot_action() for actions that reboot; ignore old ones
    # left by an action that never rebooted
    now = time.time()
    for marker in glob.glob("/tmp/mark_reboot___*"):
        try:
            if now - os.path.getmtime(marker) < 6 * 60 * 60:
                return True
        except OSError:
            pass
    return False

def get_auto_upgrade_blocker(ignore_uptime=False):
    # None if the device is in a state where it can upgrade, otherwise why not
    if not is_auto_upgrade_enabled():
        return "automatic upgrades are disabled"
    if not can_auto_upgrade():
        return "no product key"
    if get_current_beta_version() != "beta_not_installed":
        return "a beta is installed"
    if get_mynode_status() != STATE_STABLE:
        return "device is not in a stable state ({})".format(get_mynode_status())
    if is_upgrade_running() or has_recent_reboot_action() or is_shutting_down():
        return "an upgrade, reboot or shutdown is already in progress"
    if is_installing_docker_images():
        return "apps are being installed"
    if not os.access("/mnt/hdd/mynode/settings", os.W_OK):
        return "data drive is not writable"
    try:
        if int(re.sub("[^0-9]", "", get_os_drive_usage())) >= 90:
            return "OS drive is almost full"
    except Exception:
        return "OS drive usage unknown"
    if not ignore_uptime and get_system_uptime_in_seconds() < 60 * 60:
        return "device started less than an hour ago"
    return None

#----------------------------------
# Upgrade
#----------------------------------
def run_upgrade_script(expected_version):
    # Like upgrade_device(), but returns the upgrade script's own exit code
    os.system("mkdir -p /home/admin/upgrade_logs")
    os.system("cp -f /usr/bin/mynode_upgrade.sh /usr/bin/mynode_upgrade_running.sh")
    log_paths = ["/home/admin/upgrade_logs/upgrade_log_from_{}_auto_upgrade.txt".format(get_current_version()),
                 "/home/admin/upgrade_logs/upgrade_log_latest.txt"]
    logs = [open(p, "wb") for p in log_paths]
    try:
        p = subprocess.Popen(["/usr/bin/mynode_upgrade_running.sh", "expect", expected_version],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for line in iter(p.stdout.readline, b""):
            for f in logs:
                f.write(line)
                f.flush()
        return p.wait()
    finally:
        for f in logs:
            f.close()
        os.system("chown -R admin:admin /home/admin/upgrade_logs")

def auto_upgrade_device(state):
    target = state["target"]
    now = int(time.time())
    state.update(stage="running", last_attempt=now, from_version=get_current_version())
    save_auto_upgrade_state(state)
    mark_upgrade_started()

    log_message("Auto Upgrade: upgrading from v{} to v{}".format(state["from_version"], target))
    rc = run_upgrade_script(target)
    now = int(time.time())

    if rc in (UPGRADE_EXIT_NOT_VERIFIED, UPGRADE_EXIT_WRONG_VERSION):
        # Nothing was installed: no reboot, and it does not count as an attempt
        detail = "Download failed or could not be verified"
        if rc == UPGRADE_EXIT_WRONG_VERSION:
            detail = "Downloaded version was not v{}".format(target)
        state["last_result"] = {"result": "not_installed", "to": target, "time": now, "detail": detail}
        state.update(stage=None, from_version=None)
        save_auto_upgrade_state(state)
        delete_file("/tmp/upgrade_started")
        log_message("Auto Upgrade: {} (exit {}), will retry".format(detail, rc))
        return False

    if rc == 0 and not did_upgrade_fail():
        state["last_result"] = {"result": "ok", "from": state["from_version"], "to": target, "time": now}
        state.update(target=None, first_seen=None, attempts=0,
                     last_attempt=None, last_failure=None)
        log_message("Auto Upgrade: installed v{}, rebooting".format(target))
    else:
        state["attempts"] += 1
        state["last_failure"] = now
        state["last_result"] = {"result": "failed", "to": target, "time": now,
                                "detail": "Upgrade did not complete (exit {})".format(rc)}
        log_message("Auto Upgrade: v{} failed (attempt {}, exit {}), rebooting".format(target, state["attempts"], rc))
    state.update(stage=None, from_version=None)
    save_auto_upgrade_state(state)

    os.system("sync")
    time.sleep(1)
    reboot_device()
    return True

#----------------------------------
# UI
#----------------------------------
def get_auto_upgrade_status():
    state = get_auto_upgrade_state()
    scheduled = get_auto_upgrade_scheduled_time(state)
    retry = get_next_retry_time(state)
    if scheduled is not None and retry is not None:
        scheduled = max(scheduled, retry)
    scheduled_text = None
    if scheduled is not None:
        if scheduled <= time.time():
            scheduled_text = "tonight ({}-{} AM)".format(AUTO_UPGRADE_WINDOW_START_HOUR, AUTO_UPGRADE_WINDOW_END_HOUR)
        else:
            scheduled_text = format_auto_upgrade_time(scheduled)
    last_result = state["last_result"] or {}
    return {
        "enabled": is_auto_upgrade_enabled(),
        "available": can_auto_upgrade(),
        "target": state["target"],
        "skipped": state["skipped"] is not None and state["skipped"] == state["target"],
        "scheduled": scheduled_text,
        "attempts": state["attempts"],
        "weekly": state["attempts"] >= AUTO_UPGRADE_NIGHTLY_ATTEMPTS,
        "last_result": last_result,
        "last_result_time": format_auto_upgrade_time(last_result.get("time")) if last_result else None,
        "show_result": bool(last_result) and last_result.get("result") == "ok" and not last_result.get("dismissed"),
    }

def skip_auto_upgrade_version(version):
    state = get_auto_upgrade_state()
    state["skipped"] = version
    save_auto_upgrade_state(state)

def unskip_auto_upgrade_version():
    state = get_auto_upgrade_state()
    state["skipped"] = None
    save_auto_upgrade_state(state)

def dismiss_auto_upgrade_result():
    state = get_auto_upgrade_state()
    if state["last_result"]:
        state["last_result"]["dismissed"] = True
        save_auto_upgrade_state(state)

def reset_auto_upgrade_attempts():
    # The owner retried by hand. Never stops the manual upgrade itself.
    try:
        state = get_auto_upgrade_state()
        state.update(attempts=0, last_attempt=None, last_failure=None)
        save_auto_upgrade_state(state)
    except Exception as e:
        log_message("reset_auto_upgrade_attempts exception: {}".format(str(e)))
