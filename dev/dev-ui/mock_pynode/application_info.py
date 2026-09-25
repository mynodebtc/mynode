"""Mock shim for pynode/application_info.py.

App catalog, install markers, status and cache logic all stay REAL - they are
plain file/JSON operations that work against the fixture filesystem. Only the
actions that would run installer scripts are replaced with simulations that
flip the same marker files the real code reads, then trigger the simulated
reboot so the real "Installing..." page and redirect flow plays out."""
import os
import time

from _mockutil import load_real, export

_real = load_real("application_info")


def _write_install_log(action, app, lines_file):
    os.makedirs("/home/admin/upgrade_logs", exist_ok=True)
    latest = "/home/admin/upgrade_logs/upgrade_log_latest.txt"
    lines = [
        "===== {} {} (MOCKED - UI dev container) =====".format(action, app),
        "Stopping app services...",
        "Downloading {}... done".format(app),
        "Extracting files... done",
        "Running install scripts... done",
        "Enabling service...",
        "===== {} {} complete =====".format(action, app),
    ]
    for path in (latest, lines_file):
        with open(path, "w"):
            pass
    for line in lines:
        for path in (latest, lines_file):
            with open(path, "a") as f:
                f.write(line + "\n")
        time.sleep(0.6)


def _set_current_version_to_latest(app):
    try:
        info = _real.get_application(app)
        if info and info.get("latest_version") not in (None, "unknown", "error"):
            _real.set_file_contents(
                "/home/bitcoin/.mynode/{}_version".format(app), info["latest_version"])
    except Exception as e:
        _real.log_message("[mock] could not set version for {}: {}".format(app, e))


def reinstall_app(app):
    if _real.is_upgrade_running():
        return
    _real.mark_upgrade_started()
    _real.log_message("[mock] reinstall_app({}) - simulating install".format(app))
    _real.clear_application_cache()
    _write_install_log("Install", app, "/home/admin/upgrade_logs/reinstall_{}.txt".format(app))
    _real.mark_app_installed(app)
    _set_current_version_to_latest(app)
    # Newly installed apps come up enabled + running
    _real.enable_service(app)
    _real.clear_application_cache()
    time.sleep(1)
    _real.reboot_device()  # simulated (mock device_info)


def uninstall_app(app):
    _real.log_message("[mock] uninstall_app({}) - simulating uninstall".format(app))
    _real.disable_service(app)
    _real.clear_app_installed(app)
    _real.delete_file("/home/bitcoin/.mynode/{}_version".format(app))
    _real.delete_file("/mnt/hdd/mynode/settings/{}_version".format(app))
    _real.clear_application_cache()
    _write_install_log("Uninstall", app, "/home/admin/upgrade_logs/uninstall_{}.txt".format(app))


def remove_app(app):
    # Like the real remove_app for dynamic apps, but keeps the app definition
    # under /usr/share/mynode_apps so it can be "reinstalled" in dev mode.
    _real.log_message("[mock] remove_app({})".format(app))
    _real.clear_app_installed(app)
    _real.disable_service(app)
    _real.clear_application_cache()


_real.reinstall_app = reinstall_app
_real.uninstall_app = uninstall_app
_real.remove_app = remove_app

export(globals(), _real)
