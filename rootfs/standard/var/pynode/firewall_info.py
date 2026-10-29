from utilities import *
import fcntl
import glob
import os
import re
import shlex
import subprocess

# Each service gets a ufw app profile in this file. A service is allowed from the local network
# ranges below, or from anywhere when it is public.
FIREWALL_PROFILE_FILE = "/etc/ufw/applications.d/mynode"
# ufw can lose rules when two ufw commands change them at the same time, so MyNode's firewall
# changes (mynode_firewall.sh, startup, Settings) take this lock and run one at a time
FIREWALL_LOCK_FILE = "/run/mynode_firewall.lock"
FIREWALL_PUBLIC_SETTINGS_FILES = ["/mnt/hdd/mynode/settings/firewall_public_services.json",
                                  "/home/bitcoin/.mynode/firewall_public_services.json"]

# Private ranges, plus Tailscale's 100.64.0.0/10. VPN clients (10.6.0.0/24, 10.8.0.0/24) and Docker
# networks fall inside these.
FIREWALL_LOCAL_SOURCES = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"]

# ufw allows at most 15 ports per rule; a range counts as 2
FIREWALL_MAX_PORTS_PER_PROFILE = 15

# Ports that are not in an app's JSON. Entries whose id is an app's short_name are merged with that
# app's ports, and are listed in Settings only while it is installed; "app" names a different app
# whose install state an entry follows. Ports are in ufw profile syntax; a port without a protocol
# is opened for TCP and UDP.
FIREWALL_CORE_SERVICES = [
    {"id": "ssh",             "name": "SSH",                         "ports": ["22/tcp"]},
    {"id": "www",             "name": "MyNode Web UI",               "ports": ["80/tcp", "443/tcp"]},
    {"id": "local_discovery", "name": "UPnP and Local Discovery",    "ports": ["1900", "2189", "5351", "5353"]},
    {"id": "bitcoin_p2p",     "name": "Bitcoin P2P",                 "ports": ["8333/tcp", "18333/tcp"]},
    {"id": "bitcoin_rpc",     "name": "Bitcoin RPC",                 "ports": ["8332/tcp", "8335/tcp", "8336/tcp"]},
    {"id": "lightning_p2p",   "name": "Lightning P2P",               "ports": ["9735/tcp"]},
    {"id": "lnd_watchtower",  "name": "Lightning Watchtower",        "ports": ["9911/tcp"]},
    {"id": "lnd_rpc",         "name": "LND gRPC and REST",           "ports": ["10009/tcp", "10080/tcp"]},
    {"id": "lit",             "name": "Lightning Terminal",          "ports": ["8443/tcp"]},
    {"id": "lndhub",          "name": "LND Hub",                     "ports": ["3000/tcp", "3001/tcp"]},
    {"id": "btcrpcexplorer",  "name": "BTC RPC Explorer",            "ports": ["3002/tcp", "3003/tcp"]},
    {"id": "caravan",         "name": "Caravan",                     "ports": ["3020/tcp", "3021/tcp"]},
    {"id": "nut",             "name": "Network UPS Tools",           "ports": ["3493/tcp"]},
    {"id": "mempool",         "name": "Mempool",                     "ports": ["4080/tcp", "4081/tcp"]},
    {"id": "wardenterminal",  "name": "Warden Terminal",             "ports": ["5010/tcp", "5011/tcp"]},
    {"id": "usb_extras",      "name": "USB Extras",                  "ports": ["8010:8019/tcp"]},
    {"id": "electrs",         "name": "Electrum Server",             "ports": ["50001/tcp", "50002/tcp"]},
    {"id": "sphinxrelay",     "name": "Sphinx Relay",                "ports": ["53001/tcp"]},
    {"id": "btcpayserver",    "name": "BTCPay Server",               "ports": ["49392/tcp"]},
    {"id": "vpn",             "name": "VPN",                         "ports": ["51194"]},
    {"id": "glances",         "name": "Glances",                     "ports": ["61208/tcp", "61209/tcp"]},
    {"id": "joinmarket",      "name": "JoinMarket Orderbook",        "ports": ["62601/tcp", "62602/tcp"], "app": "joininbox"},
    {"id": "joinmarket_api",  "name": "JoinMarket API",              "ports": ["27183/tcp", "28183/tcp", "28283/tcp"], "app": "joininbox"},
    {"id": "datum",           "name": "DATUM",                       "ports": ["23334/tcp"]},
]

# Services reachable from anywhere unless the owner changes it in Settings
FIREWALL_DEFAULT_PUBLIC_SERVICES = ["bitcoin_p2p", "lightning_p2p", "lnd_watchtower", "vpn",
                                    "electrs", "btcpayserver", "lnbits", "lndhub", "nostrrsrelay",
                                    "sphinxrelay", "publicpool"]

# Ports earlier versions opened to any source with a bare "ufw allow <port>", besides the ports of
# the services above. Those rules are deleted.
FIREWALL_LEGACY_PORTS = ["6001", "6002", "6003", "8899", "8010:8019/tcp", "50194"]


def get_firewall_public_overrides():
    for path in FIREWALL_PUBLIC_SETTINGS_FILES:
        if os.path.isfile(path):
            data = get_dictionary_file_cache(path)
            if isinstance(data, dict):
                return {k: v for k, v in data.items() if isinstance(k, str) and isinstance(v, bool)}
    return {}

def set_firewall_public_overrides(overrides):
    for path in FIREWALL_PUBLIC_SETTINGS_FILES:
        if os.path.isdir(os.path.dirname(path)):
            set_dictionary_file_cache(overrides, path)

def get_other_firewall_profile_names():
    # Profiles installed by other packages (ufw itself ships "SSH", "WWW", ...)
    names = []
    for path in glob.glob(os.path.join(os.path.dirname(FIREWALL_PROFILE_FILE), "*")):
        if path != FIREWALL_PROFILE_FILE:
            contents = to_string(get_file_contents(path))
            names += re.findall(r"^\[(.+)\]\s*$", contents, re.MULTILINE)
    return names

def get_firewall_profile_name(name, other_names):
    name = re.sub(r"[^A-Za-z0-9 ._-]", "", name).strip()
    if name == "" or not name[0].isalnum() or name.isdigit() or name in other_names:
        name = "MyNode " + name
    return name

def get_firewall_services(apps):
    services = []
    by_id = {}
    apps_by_name = {app["short_name"]: app for app in apps}
    for s in FIREWALL_CORE_SERVICES:
        app = apps_by_name.get(s.get("app", s["id"]))
        installed = app.get("is_installed", True) if app != None else True
        service = {"id": s["id"], "name": s["name"], "ports": list(s["ports"]), "installed": installed}
        services.append(service)
        by_id[s["id"]] = service

    for app in apps:
        app_ports = [app.get("http_port"), app.get("https_port")] + list(app.get("extra_ports") or [])
        ports = []
        for p in app_ports:
            if p in [None, ""]:
                continue
            if not str(p).isdigit():
                log_message("ERROR: Invalid port {} for application {}".format(p, app["short_name"]))
                continue
            ports.append("{}/tcp".format(p))
        if app["short_name"] in by_id:
            service = by_id[app["short_name"]]
            service["ports"] += [p for p in ports if p not in service["ports"]]
        elif len(ports) > 0:
            service = {"id": app["short_name"], "name": app["name"], "ports": ports,
                       "installed": app.get("is_installed", True)}
            services.append(service)
            by_id[app["short_name"]] = service

    overrides = get_firewall_public_overrides()
    other_names = get_other_firewall_profile_names()
    used_names = []
    for service in services:
        service["default_public"] = service["id"] in FIREWALL_DEFAULT_PUBLIC_SERVICES
        # Apps that are not installed are not listed in Settings, so they stay local-only
        service["public"] = service["installed"] and overrides.get(service["id"], service["default_public"])
        name = get_firewall_profile_name(service["name"], other_names)
        if name in used_names:
            name = get_firewall_profile_name("{} {}".format(service["name"], service["id"]), other_names)
        used_names.append(name)
        service["profile_name"] = name
        service["port_text"] = ", ".join(p.replace("/tcp", "").replace(":", "-") for p in service["ports"])
    return services

def get_firewall_profiles(service):
    # Split into profiles of at most 15 ports, grouped by protocol
    profiles = []
    current = []
    count = 0
    for port in service["ports"]:
        size = 2 if ":" in port else 1
        if count + size > FIREWALL_MAX_PORTS_PER_PROFILE:
            profiles.append(current)
            current = []
            count = 0
        current.append(port)
        count += size
    if len(current) > 0:
        profiles.append(current)

    result = []
    for i, ports in enumerate(profiles):
        name = service["profile_name"] if i == 0 else "{} {}".format(service["profile_name"], i + 1)
        tcp = [p.replace("/tcp", "") for p in ports if p.endswith("/tcp")]
        entries = []
        if len(tcp) > 0:
            entries.append(",".join(tcp) + "/tcp")
        entries += [p for p in ports if not p.endswith("/tcp")]
        result.append({"name": name, "ports": "|".join(entries)})
    return result

def get_firewall_profile_text(services):
    text = "# Generated by MyNode, do not edit\n"
    for service in services:
        for profile in get_firewall_profiles(service):
            text += "\n[{}]\ntitle={}\ndescription=MyNode service {}\nports={}\n".format(
                profile["name"], service["name"].replace("\n", " "), service["id"], profile["ports"])
    return text

def get_firewall_profile_names_in_file():
    names = []
    contents = to_string(get_file_contents(FIREWALL_PROFILE_FILE))
    if contents != "ERROR":
        for line in contents.splitlines():
            m = re.match(r"^\[(.+)\]$", line.strip())
            if m:
                names.append(m.group(1))
    return names

def get_ufw_added_rules():
    output = to_string(subprocess.check_output(["ufw", "show", "added"]))
    rules = []
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("ufw "):
            rules.append(tuple(shlex.split(line)[1:]))
    return rules

def run_ufw(args):
    print("  ufw {}".format(" ".join(args)))
    try:
        subprocess.check_call(["ufw"] + list(args))
    except Exception as e:
        log_message("ERROR: ufw {} failed - {}".format(" ".join(args), str(e)))

def get_firewall_rule_app(rule):
    # Profile name used by a rule, or None
    if len(rule) == 2 and rule[0] == "allow":
        return rule[1]
    if len(rule) >= 2 and rule[-2] == "app":
        return rule[-1]
    return None

def update_firewall_rules(apps):
    with open(FIREWALL_LOCK_FILE, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        update_firewall_rules_locked(apps)

def update_firewall_rules_locked(apps):
    print("Updating firewall rules...")
    services = get_firewall_services(apps)

    desired = []
    for service in services:
        for profile in get_firewall_profiles(service):
            if service["public"]:
                desired.append(("allow", profile["name"]))
            else:
                for source in FIREWALL_LOCAL_SOURCES:
                    desired.append(("allow", "from", source, "to", "any", "app", profile["name"]))

    managed_names = set(get_firewall_profile_names_in_file())
    text = get_firewall_profile_text(services)
    if to_string(get_file_contents(FIREWALL_PROFILE_FILE)) != text.strip():
        set_file_contents(FIREWALL_PROFILE_FILE, text)
        run_ufw(["app", "update", "all"])
    managed_names.update(get_firewall_profile_names_in_file())

    current = get_ufw_added_rules()

    # Add new rules before deleting old ones, so nothing that stays open closes in between
    for rule in desired:
        if rule not in current:
            run_ufw(rule)

    for rule in current:
        if rule not in desired and get_firewall_rule_app(rule) in managed_names:
            run_ufw(("delete",) + rule)

    # Delete the "ufw allow <port>" rules (any source) earlier versions added: the ports above, and
    # any such rule with MyNode's "allow ..." comment, which covers removed features and old app
    # ports. Rules without a comment that are not MyNode ports (PiVPN's, the owner's) are kept.
    legacy_ports = set(FIREWALL_LEGACY_PORTS)
    for service in services:
        for port in service["ports"]:
            legacy_ports.add(port.replace("/tcp", ""))
    for rule in current:
        if len(rule) < 2 or rule[0] != "allow" or not re.match(r"^\d+(:\d+)?(/(tcp|udp))?$", rule[1]):
            continue
        has_mynode_comment = len(rule) == 4 and rule[2] == "comment" and rule[3].startswith("allow ")
        if rule[1] in legacy_ports or has_mynode_comment:
            run_ufw(("delete", "allow", rule[1]))
