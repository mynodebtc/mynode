#!/usr/local/bin/python3
import argparse
import logging
import time
from systemd import journal
from utilities import *
from device_info import *
from auto_upgrade import *

log = logging.getLogger('auto_upgrade')
log.addHandler(journal.JournaldLogHandler())
log.setLevel(logging.INFO)
set_logger(log)

# Run hourly by mynode_auto_upgrade.timer. Tracks newly released versions and installs one once
# its delay has passed, inside the nightly window.
def main(dry_run, now_flag):
    if not os.path.isdir("/mnt/hdd/mynode/settings"):
        log_message("Auto Upgrade: data drive not ready")
        return

    state = get_auto_upgrade_state()
    now = int(time.time())
    current = get_current_version()
    changed = reconcile_interrupted_upgrade(state, current, did_upgrade_fail(), now)

    # Track releases from the version check-in already fetched (no network use here)
    if is_clock_synchronized():
        changed = update_auto_upgrade_target(state, current, read_latest_version_file(), now) or changed
    if changed and not dry_run:
        save_auto_upgrade_state(state)

    if not is_auto_upgrade_enabled():
        return
    blocker = get_auto_upgrade_blocker(ignore_uptime=now_flag)
    if blocker:
        log_message("Auto Upgrade: not upgrading, {}".format(blocker))
        return
    if not is_clock_synchronized():
        log_message("Auto Upgrade: not upgrading, clock not synchronized")
        return

    local_hour = AUTO_UPGRADE_WINDOW_START_HOUR if now_flag else time.localtime(now).tm_hour
    reason = get_auto_upgrade_wait_reason(state, now, local_hour)
    if reason:
        log_message("Auto Upgrade: not upgrading, {}".format(reason))
        return

    # Due. Fetch the latest version again first: a release pulled from the server since the last
    # check must not be installed.
    target = state["target"]
    update_latest_version()
    now = int(time.time())
    latest = read_latest_version_file()
    if latest != target:
        update_auto_upgrade_target(state, current, latest, now)
        if not dry_run:
            save_auto_upgrade_state(state)
        log_message("Auto Upgrade: not upgrading, latest version is now {} (was {})".format(latest, target))
        return

    if dry_run:
        log_message("Auto Upgrade: dry run, would upgrade from v{} to v{}".format(current, target))
        return
    auto_upgrade_device(state)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="Log the decision without saving state or upgrading")
    parser.add_argument("--now", action="store_true",
                        help="Testing: ignore the 3-5 AM window and the recent-boot check")
    args = parser.parse_args()
    main(args.dry_run, args.now)
