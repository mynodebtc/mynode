"""Dev-only state switcher for the mocked UI dev container.

Registered by dev_server.py (never by the real app). Provides:
  - /dev/* endpoints that flip the same files/globals the real code reads
  - a floating overlay panel injected into every HTML page (inject_overlay)
No auth: the container is bound to 127.0.0.1 and is dev-only."""
import glob
import json
import os
import time

from flask import Blueprint, Response, jsonify, request, session

from _mockutil import real, get_knob, set_knob

import seed_fixture_fs
import bitcoin_info
import lightning_info
import electrum_info
import price_info
import thread_functions
import application_info
import device_info
import systemctl_info

mynode_dev = Blueprint("mynode_dev", __name__)

BITCOIN_SYNCED_FILE = "/mnt/hdd/mynode/.mynode_bitcoin_synced"

DEVICE_STATES = [
    "stable", "drive_missing", "drive_format_confirm", "drive_formatting",
    "drive_mounted", "drive_clone", "drive_full", "docker_reset",
    "gen_dhparam", "choose_network", "quicksync_download", "quicksync_copy",
    "quicksync_reset", "rootfs_read_only", "hdd_read_only", "shutting_down",
    "upgrading", "unknown",
]

THROTTLE_BITS = {
    "undervoltage": 0x10000,  # HAS_UNDERVOLTED
    "capped": 0x20000,        # HAS_CAPPED
    "throttled": 0x40000,     # HAS_THROTTLED
}


def seed_runtime_data(log_errors=False):
    """Populate/refresh the module-global caches the pages read. The real
    update functions run against the mocked data sources."""
    steps = [
        bitcoin_info.update_bitcoin_main_info,
        bitcoin_info.update_bitcoin_other_info,
        lightning_info.update_lightning_info,
        electrum_info.update_electrs_info,
        price_info.update_price_info,
        thread_functions.update_device_info,
        thread_functions.find_public_ip,
        application_info.update_application_json_cache,
    ]
    for step in steps:
        try:
            step()
        except Exception as e:
            if log_errors:
                print("[dev seed] {} failed: {}".format(step.__name__, e))
            else:
                raise
    if not get_knob("misc", {}).get("starting"):
        real("thread_functions").has_updated_btc_info = True


def autologin():
    session["logged_in"] = True
    session.permanent = True


def inject_overlay(response):
    """after_request hook: append the dev overlay script to HTML pages."""
    try:
        content_type = response.content_type or ""
        if content_type.startswith("text/html") and not response.direct_passthrough:
            body = response.get_data(as_text=True)
            if "</body>" in body and "/dev/overlay.js" not in body:
                body = body.replace("</body>", '<script src="/dev/overlay.js"></script></body>', 1)
                response.set_data(body)
    except Exception:
        pass
    return response


def _ok(**extra):
    data = {"result": "ok"}
    data.update(extra)
    return jsonify(data)


@mynode_dev.route("/dev/status")
def dev_status():
    status = "unknown"
    try:
        with open("/tmp/.mynode_status") as f:
            status = f.read().strip()
    except Exception:
        pass
    version = "?"
    latest = "?"
    try:
        with open("/usr/share/mynode/version") as f:
            version = f.read().strip()
        with open("/usr/share/mynode/latest_version") as f:
            latest = f.read().strip()
    except Exception:
        pass
    return jsonify({
        "device_state": status,
        "device_states": DEVICE_STATES,
        "bitcoin_synced": os.path.isfile(BITCOIN_SYNCED_FILE),
        "bitcoin_knob": get_knob("bitcoin", {"behind_blocks": 0}),
        "starting": bool(get_knob("misc", {}).get("starting")),
        "lnd_ready": bool(get_knob("lnd", {"ready": True}).get("ready", True)),
        "lnd_wallet": lightning_info.lnd_wallet_exists(),
        "drive": get_knob("drive", {"data": "61%", "os": "34%"}),
        "upgrade_available": version != latest,
        "warning": _current_warning_file(),
        "autologin": os.environ.get("DEV_AUTOLOGIN") == "1",
        "premium": not device_info.is_community_edition(),
    })


def _current_warning_file():
    try:
        with open("/tmp/get_throttled_data") as f:
            value = int(f.read().strip(), 16)
        for name, bit in THROTTLE_BITS.items():
            if value & bit:
                return name
    except Exception:
        pass
    return "none"


@mynode_dev.route("/dev/state")
def dev_state():
    value = request.args.get("value", "")
    if value not in DEVICE_STATES:
        return jsonify({"result": "error", "message": "unknown state", "valid": DEVICE_STATES}), 400
    with open("/tmp/.mynode_status", "w") as f:
        f.write(value)
    if value == "drive_clone":
        clone_state = request.args.get("clone", "detecting")
        with open("/tmp/.clone_state", "w") as f:
            f.write(clone_state)
        with open("/tmp/.clone_progress", "w") as f:
            f.write("42.00% complete (289 GB / 689 GB) - mocked")
    return _ok(state=value)


@mynode_dev.route("/dev/sync")
def dev_sync():
    synced = request.args.get("synced", "1") == "1"
    if synced:
        set_knob("bitcoin", {"behind_blocks": 0})
        if not os.path.isfile(BITCOIN_SYNCED_FILE):
            open(BITCOIN_SYNCED_FILE, "a").close()
    else:
        knob = {"behind_blocks": int(request.args.get("behind", 340000))}
        if request.args.get("progress"):
            knob["progress"] = float(request.args.get("progress"))
        set_knob("bitcoin", knob)
        if os.path.isfile(BITCOIN_SYNCED_FILE):
            os.remove(BITCOIN_SYNCED_FILE)
    bitcoin_info.update_bitcoin_main_info()
    open("/tmp/homepage_needs_refresh", "a").close()
    return _ok(synced=synced)


@mynode_dev.route("/dev/starting")
def dev_starting():
    starting = request.args.get("value", "1") == "1"
    misc = get_knob("misc", {})
    misc["starting"] = starting
    set_knob("misc", misc)
    real("thread_functions").has_updated_btc_info = not starting
    return _ok(starting=starting)


@mynode_dev.route("/dev/apps")
def dev_apps():
    apps = []
    for app in application_info.get_all_applications(order_by="alphabetic"):
        if app.get("show_on_marketplace_page") or app.get("show_on_application_page"):
            apps.append({
                "short_name": app["short_name"],
                "name": app["name"],
                "is_installed": app["is_installed"],
                "is_enabled": app["is_enabled"],
            })
    return jsonify(apps)


@mynode_dev.route("/dev/app")
def dev_app():
    name = request.args.get("name", "")
    installed = request.args.get("installed", "1") == "1"
    if not application_info.is_application_valid(name):
        return jsonify({"result": "error", "message": "unknown app"}), 400
    if installed:
        application_info.mark_app_installed(name)
        try:
            info = application_info.get_application(name)
            if info and info.get("latest_version") not in (None, "unknown", "error"):
                with open("/home/bitcoin/.mynode/{}_version".format(name), "w") as f:
                    f.write(info["latest_version"])
        except Exception:
            pass
        application_info.enable_service(name)
    else:
        application_info.disable_service(name)
        application_info.clear_app_installed(name)
    application_info.clear_application_cache()
    application_info.trigger_application_refresh()
    open("/tmp/homepage_needs_refresh", "a").close()
    return _ok(app=name, installed=installed)


@mynode_dev.route("/dev/service")
def dev_service():
    name = request.args.get("name", "")
    status = request.args.get("status", "running")
    if not name or status not in ("running", "stopped", "failed", "disabled"):
        return jsonify({"result": "error", "message": "usage: /dev/service?name=x&status=running|stopped|failed|disabled"}), 400
    os.makedirs("/tmp/mock_services", exist_ok=True)
    with open(os.path.join("/tmp/mock_services", name), "w") as f:
        f.write(status)
    systemctl_info.clear_service_enabled_cache()
    return _ok(service=name, status=status)


@mynode_dev.route("/dev/warning")
def dev_warning():
    name = request.args.get("name", "clear")
    dev_info_real = real("device_info")
    if name in THROTTLE_BITS:
        with open("/tmp/get_throttled_data", "w") as f:
            f.write("0x{:x}".format(THROTTLE_BITS[name]))
        # Re-arm in case the warning was previously skipped via the UI
        for marker in glob.glob("/tmp/warning_skipped_*"):
            os.remove(marker)
        dev_info_real.reload_throttled_data()
    elif name == "fsck":
        open("/tmp/fsck_error", "a").close()
        with open("/tmp/fsck_results", "w") as f:
            f.write("(mock) fsck found and repaired 3 inode errors on /dev/sda1")
    elif name == "usb":
        open("/tmp/usb_error", "a").close()
    elif name == "clear":
        for path in ["/tmp/get_throttled_data", "/tmp/fsck_error", "/tmp/fsck_results", "/tmp/usb_error"]:
            if os.path.exists(path):
                os.remove(path)
        for marker in glob.glob("/tmp/warning_skipped_*"):
            os.remove(marker)
        dev_info_real.cached_data["get_throttled_data"] = ""
    else:
        return jsonify({"result": "error", "message": "unknown warning", "valid": list(THROTTLE_BITS) + ["fsck", "usb", "clear"]}), 400
    return _ok(warning=name)


@mynode_dev.route("/dev/drive")
def dev_drive():
    knob = get_knob("drive", {"data": "61%", "os": "34%"})
    for key in ("data", "os"):
        if request.args.get(key):
            value = request.args.get(key)
            knob[key] = value if value.endswith("%") else value + "%"
    set_knob("drive", knob)
    return _ok(drive=knob)


@mynode_dev.route("/dev/lnd")
def dev_lnd():
    knob = get_knob("lnd", {"ready": True})
    if request.args.get("ready") is not None:
        knob["ready"] = request.args.get("ready") == "1"
        set_knob("lnd", knob)
        real("lightning_info").lnd_ready = knob["ready"]
        lightning_info.update_lightning_info()
    if request.args.get("wallet") is not None:
        wallet_file = lightning_info.get_lightning_wallet_file()
        if request.args.get("wallet") == "1":
            open(wallet_file, "a").close()
        elif os.path.isfile(wallet_file):
            os.remove(wallet_file)
    return _ok(lnd=knob, wallet=lightning_info.lnd_wallet_exists())


@mynode_dev.route("/dev/edition")
def dev_edition():
    """Toggle between community edition (default) and a mocked premium
    device (product key present + healthy check-in data)."""
    premium = request.args.get("premium", "1") == "1"
    if premium:
        device_info.unset_skipped_product_key()
        with open("/home/bitcoin/.mynode/.product_key", "w") as f:
            f.write("MOCKPRODUCTKEY123456")
        device_info.delete_product_key_error()
        with open("/tmp/check_in_response.json", "w") as f:
            json.dump({"status": "OK",
                       "support": {"active": True, "days_remaining": 300},
                       "premium_plus": {"active": False, "days_remaining": 0}}, f)
    else:
        device_info.delete_product_key()
        device_info.set_skipped_product_key()
        if os.path.exists("/tmp/check_in_response.json"):
            os.remove("/tmp/check_in_response.json")
    return _ok(premium=premium)


@mynode_dev.route("/dev/upgrade_available")
def dev_upgrade_available():
    with open("/usr/share/mynode/version") as f:
        version = f.read().strip()
    latest = "v99.9" if request.args.get("value", "1") == "1" else version
    with open("/usr/share/mynode/latest_version", "w") as f:
        f.write(latest)
    return _ok(current=version, latest=latest)


@mynode_dev.route("/dev/reboot")
def dev_reboot():
    device_info.reboot_device()
    return _ok(message="simulated reboot started")


@mynode_dev.route("/dev/shutdown")
def dev_shutdown():
    device_info.shutdown_device()
    return _ok(message="simulated shutdown started (auto power-on in ~15s)")


@mynode_dev.route("/dev/reset")
def dev_reset():
    device_info.delete_product_key()
    device_info.set_skipped_product_key()
    if os.path.exists("/tmp/check_in_response.json"):
        os.remove("/tmp/check_in_response.json")
    seed_fixture_fs.ensure(force=True)
    set_knob("lnd", {"ready": True})
    set_knob("misc", {"starting": False})
    real("lightning_info").lnd_ready = True
    real("device_info").cached_data["get_throttled_data"] = ""
    application_info.clear_application_cache()
    systemctl_info.clear_service_enabled_cache()
    seed_runtime_data(log_errors=True)
    return _ok(message="fixture state restored")


@mynode_dev.route("/dev/panel")
def dev_panel():
    return Response(
        "<!DOCTYPE html><html><head><title>myNode UI Dev Panel</title></head>"
        "<body style='background:#1c1f26;color:#eee;font-family:monospace;'>"
        "<h2 style='padding:16px;'>myNode UI dev panel</h2>"
        "<p style='padding:0 16px;'>Use the floating DEV button (bottom-right). "
        "It is injected into every page of the UI as well.</p>"
        "<script src='/dev/overlay.js'></script></body></html>",
        mimetype="text/html")


@mynode_dev.route("/dev/overlay.js")
def dev_overlay_js():
    return Response(_OVERLAY_JS, mimetype="application/javascript")


_OVERLAY_JS = r"""
(function () {
  if (window.__mynodeDevPanel) return;
  window.__mynodeDevPanel = true;

  var css = [
    "#mnDevBtn{position:fixed;bottom:14px;right:14px;z-index:2147483646;background:#e67e22;color:#fff;",
    "font:bold 13px/1 monospace;padding:9px 12px;border-radius:6px;cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,.5);}",
    "#mnDevPanel{position:fixed;bottom:52px;right:14px;z-index:2147483647;width:290px;max-height:78vh;overflow-y:auto;",
    "background:#20242c;color:#dce1e8;font:12px/1.5 monospace;border:1px solid #444;border-radius:8px;",
    "box-shadow:0 4px 18px rgba(0,0,0,.6);padding:10px;display:none;text-align:left;}",
    "#mnDevPanel h4{margin:10px 0 4px;color:#e67e22;font-size:12px;border-bottom:1px solid #333;}",
    "#mnDevPanel button{background:#39404d;color:#dce1e8;border:1px solid #555;border-radius:4px;",
    "margin:2px 2px 2px 0;padding:3px 7px;cursor:pointer;font:11px monospace;}",
    "#mnDevPanel button:hover{background:#4a5364;}",
    "#mnDevPanel select,#mnDevPanel input{background:#161a20;color:#dce1e8;border:1px solid #555;",
    "border-radius:4px;font:11px monospace;padding:2px;max-width:120px;}",
    "#mnDevPanel .on{background:#2e7d32;}",
    "#mnDevApps div{display:flex;justify-content:space-between;align-items:center;padding:1px 0;}"
  ].join("");
  var style = document.createElement("style");
  style.textContent = css;
  document.head.appendChild(style);

  var btn = document.createElement("div");
  btn.id = "mnDevBtn";
  btn.textContent = "DEV";
  document.body.appendChild(btn);

  var panel = document.createElement("div");
  panel.id = "mnDevPanel";
  document.body.appendChild(panel);

  function call(url) {
    return fetch(url).then(function (r) { return r.json(); });
  }
  function act(url) {
    call(url).then(function () { location.reload(); });
  }

  function section(title) {
    var h = document.createElement("h4");
    h.textContent = title;
    panel.appendChild(h);
    var div = document.createElement("div");
    panel.appendChild(div);
    return div;
  }
  function button(parent, label, fn, on) {
    var b = document.createElement("button");
    b.textContent = label;
    if (on) b.className = "on";
    b.onclick = fn;
    parent.appendChild(b);
    return b;
  }

  function build(st) {
    panel.innerHTML = "";

    var head = document.createElement("div");
    head.innerHTML = "<b>myNode UI dev panel</b>";
    panel.appendChild(head);

    // Device state
    var s1 = section("Device state");
    var sel = document.createElement("select");
    st.device_states.forEach(function (s) {
      var o = document.createElement("option");
      o.value = s; o.textContent = s;
      if (s === st.device_state) o.selected = true;
      sel.appendChild(o);
    });
    sel.onchange = function () { act("/dev/state?value=" + sel.value); };
    s1.appendChild(sel);

    // Bitcoin
    var s2 = section("Bitcoin");
    button(s2, "synced", function () { act("/dev/sync?synced=1"); }, st.bitcoin_synced);
    button(s2, "syncing 62%", function () { act("/dev/sync?synced=0&progress=0.62&behind=344000"); }, !st.bitcoin_synced);
    button(s2, "syncing 12%", function () { act("/dev/sync?synced=0&progress=0.12&behind=796000"); });
    button(s2, "starting page " + (st.starting ? "off" : "on"), function () {
      act("/dev/starting?value=" + (st.starting ? "0" : "1"));
    }, st.starting);

    // Lightning
    var s3 = section("Lightning");
    button(s3, "ready", function () { act("/dev/lnd?ready=1"); }, st.lnd_ready);
    button(s3, "not ready", function () { act("/dev/lnd?ready=0"); }, !st.lnd_ready);
    button(s3, st.lnd_wallet ? "remove wallet" : "create wallet", function () {
      act("/dev/lnd?wallet=" + (st.lnd_wallet ? "0" : "1"));
    });

    // Warnings
    var s4 = section("Warnings");
    ["undervoltage", "throttled", "capped", "fsck", "usb"].forEach(function (w) {
      button(s4, w, function () { act("/dev/warning?name=" + w); }, st.warning === w);
    });
    button(s4, "clear", function () { act("/dev/warning?name=clear"); });

    // System
    var s5 = section("System");
    button(s5, "drive 97% full", function () { act("/dev/drive?data=97%25"); },
           st.drive && st.drive.data === "97%");
    button(s5, "drive 61%", function () { act("/dev/drive?data=61%25"); });
    button(s5, "upgrade banner " + (st.upgrade_available ? "off" : "on"), function () {
      act("/dev/upgrade_available?value=" + (st.upgrade_available ? "0" : "1"));
    }, st.upgrade_available);
    button(s5, st.premium ? "community edition" : "premium edition", function () {
      act("/dev/edition?premium=" + (st.premium ? "0" : "1"));
    }, st.premium);
    button(s5, "reboot", function () { act("/dev/reboot"); });
    button(s5, "shutdown", function () { act("/dev/shutdown"); });
    button(s5, "RESET ALL", function () {
      if (confirm("Restore all mocked state to defaults?")) act("/dev/reset");
    });

    // Apps
    var s6 = section("Apps (install / uninstall)");
    var appsDiv = document.createElement("div");
    appsDiv.id = "mnDevApps";
    appsDiv.textContent = "loading...";
    s6.appendChild(appsDiv);
    call("/dev/apps").then(function (apps) {
      appsDiv.innerHTML = "";
      apps.forEach(function (a) {
        var row = document.createElement("div");
        var name = document.createElement("span");
        name.textContent = a.short_name;
        name.style.color = a.is_installed ? "#7bd88f" : "#8a919e";
        row.appendChild(name);
        var b = document.createElement("button");
        b.textContent = a.is_installed ? "uninstall" : "install";
        b.onclick = function () {
          act("/dev/app?name=" + a.short_name + "&installed=" + (a.is_installed ? "0" : "1"));
        };
        row.appendChild(b);
        appsDiv.appendChild(row);
      });
    }).catch(function () { appsDiv.textContent = "failed to load apps"; });
  }

  btn.onclick = function () {
    if (panel.style.display === "block") {
      panel.style.display = "none";
      return;
    }
    panel.style.display = "block";
    panel.innerHTML = "loading...";
    call("/dev/status").then(build).catch(function (e) {
      panel.textContent = "failed to load /dev/status: " + e;
    });
  };
})();
"""
