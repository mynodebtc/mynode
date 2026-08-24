"""Build the fixture filesystem for the mocked UI dev container.

The real myNode code reads absolute paths (/mnt/hdd/..., /home/bitcoin/...,
/usr/share/mynode/..., /tmp/...) as inline literals, so instead of trying to
intercept paths we recreate the device's filesystem inside the container.

Idempotent: safe to run on every container start and on werkzeug reloads.
Knob/state files that a developer may have changed via the dev panel are only
reset when force=True (the /dev/reset endpoint).
"""
import json
import os
import shutil
import stat
import time

DEV_DIR = os.path.dirname(os.path.abspath(__file__))
FIXTURES_DIR = os.path.join(DEV_DIR, "fixtures")
FAKE_BIN_DIR = os.path.join(DEV_DIR, "fake_bin")
SHARE_SOURCE_DIR = "/opt/mynode/share"  # repo's usr/share/mynode (ro mount)

# Legacy apps that appear "installed" by default in the mocked UI. Everything
# else shows up in the marketplace as installable.
DEFAULT_INSTALLED_APPS = [
    "bitcoin", "lnd", "loop", "pool", "lndconnect",
    "electrs", "btcrpcexplorer", "mempool", "rtl", "thunderhub", "lndhub",
    "tor", "vpn", "netdata",
]

# Scripts/binaries referenced by the real code that just need to exist and
# succeed. Installed as copies of fake_bin/noop.
NOOP_BINS = [
    "reboot", "shutdown", "ufw", "killall", "docker", "xxd", "hdparm",
    "bitcoind", "lnd", "lncli", "loopd", "poold", "litd", "electrs", "tor",
    "mynode_chpasswd.sh", "mynode_stop_critical_services.sh",
    "mynode_get_latest_version.sh", "mynode_gen_cert.sh",
    "mynode_gen_debug_tarball.sh", "mynode_reinstall_app.sh",
    "mynode_uninstall_app.sh", "mynode_upgrade.sh",
    "mynode_upgrade_running.sh", "mynode-install-custom-bitcoin",
    "mynode-get-quicksync-progress", "create_lnd_wallet.tcl",
    "mynode_restart_quicksync.sh", "mynode_stop_quicksync.sh",
]


def _write(path, contents, overwrite=True):
    if not overwrite and os.path.exists(path):
        return
    with open(path, "w") as f:
        f.write(contents)


def _touch(path):
    if not os.path.exists(path):
        open(path, "a").close()


def _load_fixture(name):
    with open(os.path.join(FIXTURES_DIR, name)) as f:
        return json.load(f)


def install_fake_bins():
    """Install fake binaries into /usr/bin.

    The real code calls many of these via absolute /usr/bin/... paths, so PATH
    manipulation is not enough - they must exist at /usr/bin inside the
    container.
    """
    for name in os.listdir(FAKE_BIN_DIR):
        if name == "noop":
            continue
        dst = os.path.join("/usr/bin", name)
        shutil.copyfile(os.path.join(FAKE_BIN_DIR, name), dst)
        os.chmod(dst, 0o755)

    noop_src = os.path.join(FAKE_BIN_DIR, "noop")
    for name in NOOP_BINS:
        dst = os.path.join("/usr/bin", name)
        if os.path.basename(dst) in os.listdir(FAKE_BIN_DIR):
            continue  # a dedicated fake exists
        shutil.copyfile(noop_src, dst)
        os.chmod(dst, 0o755)

    os.makedirs("/usr/bin/service_scripts", exist_ok=True)


def seed_share_dir():
    """Copy the repo's /usr/share/mynode content into place and add the files
    the web UI expects that only exist on a provisioned device."""
    os.makedirs("/usr/share/mynode", exist_ok=True)
    if os.path.isdir(SHARE_SOURCE_DIR):
        shutil.copytree(SHARE_SOURCE_DIR, "/usr/share/mynode", dirs_exist_ok=True)

    version = "unknown"
    try:
        with open("/usr/share/mynode/version") as f:
            version = f.read().strip()
    except Exception:
        pass
    # No upgrade banner by default (latest == current). The dev panel can bump
    # latest_version to exercise the upgrade banner.
    _write("/usr/share/mynode/latest_version", version, overwrite=False)
    _write(
        "/usr/share/mynode/changelog",
        "=== myNode {v} (mocked changelog) ===\n"
        "- This device is running the mocked UI dev container\n"
        "- Sample changelog entry two\n"
        "- Sample changelog entry three\n".format(v=version),
        overwrite=False,
    )
    os.makedirs("/usr/share/mynode_apps", exist_ok=True)


def seed_data_drive():
    """Populate the tmpfs at /mnt/hdd like a provisioned data drive."""
    settings = "/mnt/hdd/mynode/settings"
    os.makedirs(settings, exist_ok=True)
    os.makedirs("/mnt/hdd/mynode/bitcoin", exist_ok=True)
    os.makedirs("/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet", exist_ok=True)
    os.makedirs("/mnt/hdd/mynode/electrs/bitcoin", exist_ok=True)
    os.makedirs("/mnt/hdd/mynode/quicksync", exist_ok=True)
    _touch("/mnt/hdd/.mynode")

    # Bitcoin looks synced by default (the dev panel can flip this)
    _touch("/mnt/hdd/mynode/.mynode_bitcoin_synced")
    _touch("/mnt/hdd/mynode/.mynode_bitcoin_synced_at_least_once")

    _write(os.path.join(settings, ".btcrpcpw"), "mock_rpc_password", overwrite=False)
    _write(
        os.path.join(settings, "ui.json"),
        json.dumps({
            "darkmode": False,
            "price_ticker": True,
            "pinned_bitcoin_details": False,
            "pinned_lightning_details": False,
            "background": "digital",
        }),
        overwrite=False,
    )
    # QuickSync disabled: hides sync-related noise on the settings page
    _touch(os.path.join(settings, "quicksync_disabled"))

    # Bitcoin config + a sample debug log (the "bitcoin" log page tails it)
    if os.path.isfile("/usr/share/mynode/bitcoin.conf"):
        if not os.path.isfile("/mnt/hdd/mynode/bitcoin/bitcoin.conf"):
            shutil.copyfile("/usr/share/mynode/bitcoin.conf", "/mnt/hdd/mynode/bitcoin/bitcoin.conf")
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ")
    _write(
        "/mnt/hdd/mynode/bitcoin/debug.log",
        "".join(
            "{} [mock] UpdateTip: new best=00000000000000000000mock{:04d} height={} progress=0.999999\n".format(now, i, 905114 + i)
            for i in range(10)
        ),
        overwrite=False,
    )

    # LND files: wallet exists, macaroon + tls cert present
    _touch("/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/wallet.db")
    _touch("/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/admin.macaroon")
    _touch("/mnt/hdd/mynode/lnd/tls.cert")
    if os.path.isfile("/usr/share/mynode/lnd.conf"):
        if not os.path.isfile("/mnt/hdd/mynode/lnd/lnd.conf"):
            shutil.copyfile("/usr/share/mynode/lnd.conf", "/mnt/hdd/mynode/lnd/lnd.conf")


def seed_home_dirs():
    home = "/home/bitcoin/.mynode"
    os.makedirs(home, exist_ok=True)
    os.makedirs("/home/admin/upgrade_logs", exist_ok=True)
    os.makedirs("/home/bitcoin/lnd_backup", exist_ok=True)

    # Non-default hash so the "please change your password" warning is hidden
    _write(os.path.join(home, ".hashedpw"), "mocked_password_hash_not_default", overwrite=False)

    # Channel backup exists (LND page)
    _touch("/home/bitcoin/lnd_backup/channel.backup")


def seed_edition(premium=True, force=False):
    """Set the device edition. The container defaults to premium (product key
    present + healthy check-in) so premium-only UI (onion URLs, support status)
    renders. On a warm restart the current edition is preserved unless force is
    set; the dev panel toggles it at runtime via /dev/edition."""
    home = "/home/bitcoin/.mynode"
    settings = "/mnt/hdd/mynode/settings"
    pk_files = [os.path.join(home, ".product_key"), os.path.join(settings, ".product_key")]
    skip_files = [os.path.join(home, ".product_key_skipped"),
                  os.path.join(settings, ".product_key_skipped")]
    checkin = "/tmp/check_in_response.json"

    # Preserve a session's edition choice across warm restarts
    already_set = any(os.path.exists(p) for p in pk_files + skip_files)
    if already_set and not force:
        return

    if premium:
        for p in skip_files:
            if os.path.exists(p):
                os.remove(p)
        for p in pk_files:
            _write(p, "MOCKPRODUCTKEY123456")
        _write(checkin, json.dumps({
            "status": "OK",
            "support": {"active": True, "days_remaining": 300},
        }))
    else:
        for p in pk_files:
            if os.path.exists(p):
                os.remove(p)
        for p in skip_files:
            _touch(p)
        if os.path.exists(checkin):
            os.remove(checkin)


def seed_installed_apps(force=False):
    """Mark the default set of apps as installed and generate version files."""
    # Generate <app>_version_latest files from the real version definitions
    os.system("/usr/bin/mynode_update_latest_version_files.sh")

    if force:
        # Drop install markers added via the dev panel
        for f in os.listdir("/home/bitcoin/.mynode"):
            if f.startswith("install_") and f[len("install_"):] not in DEFAULT_INSTALLED_APPS:
                os.remove(os.path.join("/home/bitcoin/.mynode", f))

    seed_markers = force or not _dev_panel_touched_apps()
    for app in DEFAULT_INSTALLED_APPS:
        marker = "/home/bitcoin/.mynode/install_" + app
        if seed_markers:
            _touch(marker)
        # Current version matches latest so nothing shows as upgradable
        latest_file = "/home/bitcoin/.mynode/{}_version_latest".format(app)
        version_file = "/home/bitcoin/.mynode/{}_version".format(app)
        if os.path.isfile(latest_file) and not os.path.isfile(version_file):
            shutil.copyfile(latest_file, version_file)


_apps_seeded_marker = "/tmp/.mock_apps_seeded"


def _dev_panel_touched_apps():
    # After first seeding, don't fight the developer's install/uninstall
    # actions on subsequent (idempotent) runs.
    if os.path.isfile(_apps_seeded_marker):
        return True
    _touch(_apps_seeded_marker)
    return False


def seed_services(force=False):
    """Seed /tmp/mock_services from fixtures/services.json (used by both the
    python systemctl mock and the fake systemctl binary)."""
    os.makedirs("/tmp/mock_services", exist_ok=True)
    services = _load_fixture("services.json")
    for name, state in services.items():
        path = os.path.join("/tmp/mock_services", name)
        if force or not os.path.exists(path):
            _write(path, state)
        # Real code also checks/creates <name>_enabled marker files
        enabled_marker = "/mnt/hdd/mynode/settings/{}_enabled".format(name)
        if state != "disabled":
            _touch(enabled_marker)
        elif force and os.path.exists(enabled_marker):
            os.remove(enabled_marker)


def seed_onion_hostnames():
    """Mock tor hidden-service hostnames so onion URLs render in premium mode
    (community edition shows 'not_available' regardless)."""
    services = ["mynode", "mynode_ssh", "mynode_btc", "mynode_lnd",
                "mynode_electrs", "mynode_lndhub", "mynode_lnbits",
                "mynode_btcpay", "mynode_sphinx", "mynode_rtl",
                "mynode_btcrpcexplorer", "mynode_mempool", "mynode_thunderhub"]
    for service in services:
        folder = os.path.join("/var/lib/tor", service)
        os.makedirs(folder, exist_ok=True)
        _write(os.path.join(folder, "hostname"),
               "{}mockmockmockmockmockmockmockmockmockmockmockmockmock.onion\n".format(
                   service.replace("_", "")[:9]),
               overwrite=False)


def seed_tmp_state(force=False):
    os.makedirs("/tmp/mock_state", exist_ok=True)
    os.makedirs("/tmp/flask_uploads", exist_ok=True)
    os.makedirs("/opt/mynode/custom", exist_ok=True)
    os.makedirs("/var/log", exist_ok=True)

    _write("/tmp/.mynode_status", "stable", overwrite=force)
    # Uptime gate in index() requires > 180s; pretend we booted 2 hours ago
    if force or not os.path.isfile("/tmp/fake_boot_time"):
        _write("/tmp/fake_boot_time", str(time.time() - 7200))

    _write("/tmp/lnd_deposit_address", "bc1qmockdepositaddressxxxxxxxxxxxxxxxxxxxxx", overwrite=False)
    _write("/tmp/mock_state/bitcoin.json", json.dumps({"behind_blocks": 0}), overwrite=force)
    _write("/tmp/mock_state/drive.json", json.dumps({"data": "61%", "os": "34%"}), overwrite=force)

    if force:
        # Clear dev-panel side effects
        for f in os.listdir("/tmp"):
            if f.startswith("mark_reboot___") or f.startswith("warning_skipped_"):
                os.remove(os.path.join("/tmp", f))
        for f in ["/tmp/get_throttled_data", "/tmp/fsck_error", "/tmp/fsck_results",
                  "/tmp/usb_error", "/tmp/oom_error", "/tmp/upgrade_started",
                  "/tmp/shutting_down", "/tmp/skip_base_upgrades"]:
            if os.path.exists(f):
                os.remove(f)
        _touch("/mnt/hdd/mynode/.mynode_bitcoin_synced")
        version = "unknown"
        try:
            with open("/usr/share/mynode/version") as f:
                version = f.read().strip()
        except Exception:
            pass
        _write("/usr/share/mynode/latest_version", version)


def ensure(force=False):
    install_fake_bins()
    seed_share_dir()
    seed_data_drive()
    seed_home_dirs()
    seed_edition(premium=True, force=force)
    seed_onion_hostnames()
    seed_services(force=force)
    seed_installed_apps(force=force)
    seed_tmp_state(force=force)


if __name__ == "__main__":
    ensure()
    print("[seed_fixture_fs] fixture filesystem ready")
