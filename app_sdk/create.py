#!/usr/bin/env python3
# Create a new MyNode application from the template in app_sdk/sampleapp.
#
#   app_sdk/create.py              Create a new app
#   app_sdk/create.py check <app>  Check an app for missing files, placeholders, download pins and its ports
#   app_sdk/create.py check_doc    Check the settings table in doc/applications.md
#   app_sdk/create.py push <app> <device ip>  Copy an app to a device and install it
#
# The new app is written to rootfs/standard/usr/share/mynode_apps/<short_name>.
# See doc/applications.md for the app layout and all JSON settings.

import os
import re
import sys
import json
import shlex
import shutil
import subprocess
from argparse import ArgumentParser

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE_DIR = os.path.join(REPO_DIR, "app_sdk/sampleapp")
APPS_DIR = os.path.join(REPO_DIR, "rootfs/standard/usr/share/mynode_apps")
HASHES_SCRIPT = "scripts/print_app_download_hashes.sh"
APP_INFO_FILE = "rootfs/standard/var/pynode/application_info.py"
APP_DOC_FILE = "doc/applications.md"
BUILTIN_APPS_FILE = "rootfs/standard/usr/share/mynode/application_info.json"

# A Docker port mapping: "[ip:]host_port:container_port[/protocol]"
PORT_MAPPING = r'((?:\d{1,3}(?:\.\d{1,3}){3}:)?\d+:\d+(?:/[a-z]+)?)'

# Fields MyNode fills in itself. An app can set them, but they are not settings and are
# left out of the documented table.
RUNTIME_FIELDS = ["current_version", "has_custom_version", "is_enabled", "release_version", "screenshots", "tor_address"]

# Documented fields that application_info.py never reads
DOC_ONLY_FIELDS = ["sdk_version", "supports_app_page"]


######################################################################################
## Prompts
######################################################################################
def prompt_yes_no(prompt, default_val=""):
    while True:
        default_prompt = "(yes/no)"
        if default_val != "":
            default_val = default_val.lower()
            if default_val in ["y", "yes"]:
                default_val = True
                default_prompt = "(Yes/no)"
            if default_val in ["n", "no"]:
                default_val = False
                default_prompt = "(yes/No)"

        answer = input("{} {} : ".format(prompt, default_prompt)).lower().strip()
        if answer in ["y", "yes"]:
            return True
        elif answer in ["n", "no"]:
            return False
        elif answer == "" and default_val != "":
            return default_val

def prompt_string(prompt, default_val=""):
    while True:
        default_prompt = ""
        if default_val != "":
            default_prompt = " ({})".format(default_val)
        answer = input("{}{} : ".format(prompt, default_prompt)).strip()
        if answer != "":
            return answer
        elif default_val != "":
            return default_val

def prompt_integer(prompt, default_val=""):
    while True:
        default_prompt = ""
        if default_val != "":
            default_prompt = " ({})".format(default_val)
        answer = input("{}{} : ".format(prompt, default_prompt)).strip()
        if answer != "":
            try:
                return int(answer)
            except ValueError:
                continue
        elif default_val != "":
            return int(default_val)


######################################################################################
## File helpers
######################################################################################
def generate_short_name(full_name):
    return re.sub(r'[^a-z_]', '', full_name.lower())

def replace_string_in_file(path, search, replace):
    if not os.path.isfile(path):
        return
    with open(path, "r") as f:
        contents = f.read()
    with open(path, "w") as f:
        f.write(contents.replace(str(search), str(replace)))

def update_app_info(app_json_path, key, value):
    with open(app_json_path, "r") as f:
        app_data = json.load(f)
    app_data[key] = value
    with open(app_json_path, "w") as f:
        json.dump(app_data, f, indent=4)
        f.write("\n")

def remove_app_info(app_json_path, key):
    with open(app_json_path, "r") as f:
        app_data = json.load(f)
    app_data.pop(key, None)
    with open(app_json_path, "w") as f:
        json.dump(app_data, f, indent=4)
        f.write("\n")


######################################################################################
## Checks
######################################################################################
def check_app(short_name):
    app_dir = os.path.join(APPS_DIR, short_name)
    errors = []
    warnings = []

    if not os.path.isdir(app_dir):
        return ["No app named {} in {}".format(short_name, APPS_DIR)], warnings

    try:
        with open("{}/{}.json".format(app_dir, short_name)) as f:
            app_data = json.load(f)
    except IOError:
        return ["Missing required file: {}.json".format(short_name)], warnings
    except ValueError as e:
        return ["{}.json is not valid JSON: {}".format(short_name, e)], warnings

    if app_data.get("short_name") != short_name:
        errors.append('short_name in {}.json must be "{}"'.format(short_name, short_name))

    required_files = ["{}.png".format(short_name)]
    for script in ["install", "uninstall", "pre", "post"]:
        required_files.append("scripts/{}_{}.sh".format(script, short_name))
    for f in required_files:
        if not os.path.isfile(os.path.join(app_dir, f)):
            errors.append("Missing required file: {}".format(f))

    # Leftover template placeholders
    for root, dirs, files in os.walk(app_dir):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            path = os.path.join(root, name)
            try:
                with open(path) as f:
                    if "FILL_IN" in f.read():
                        warnings.append("Placeholder FILL_IN value in {}".format(os.path.relpath(path, app_dir)))
            except (UnicodeDecodeError, IOError):
                pass

    # Downloads must be pinned to a hash
    if app_downloads_source(app_data):
        pinned = app_data.get("download_source_sha256", "")
        if not pinned or pinned.split()[0] != app_data.get("latest_version"):
            warnings.append("download_source_sha256 is missing or does not match latest_version")

    # Docker images must be pinned to a digest for the tag latest_version pulls
    try:
        with open(os.path.join(app_dir, "scripts/install_{}.sh".format(short_name))) as f:
            install_src = f.read()
    except IOError:
        install_src = ""
    docker_images = get_marketplace_docker_images(short_name)
    if re.search(r'^[^#\n]*pull_app_docker_image', install_src, re.M) and not docker_images:
        warnings.append("Install script pulls a Docker image, but {} is not in MARKETPLACE_DOCKER_IMAGES in {}".format(short_name, HASHES_SCRIPT))
    env_vars = app_data.get("install_env_vars") or {}
    for var, image, tag_template in docker_images:
        tag = tag_template.replace("{VERSION}", str(app_data.get("latest_version", "")))
        # The pin is in install_env_vars if set there, otherwise in the install script
        pinned = env_vars.get(var)
        if pinned == None:
            m = re.search(r'^\s*{}="([^"]*)"'.format(re.escape(var)), install_src, re.M)
            pinned = m.group(1) if m else ""
        if "{VERSION}" in pinned:
            warnings.append("{} uses {{VERSION}}; pin the literal tag {} so a stale digest fails the install".format(var, tag))
        elif len(pinned.split()) != 2 or pinned.split()[0] != tag:
            warnings.append("{} is missing or does not match {}:{}".format(var, image, tag))

    port_errors, port_warnings = check_app_ports(short_name, app_dir, app_data)
    errors += port_errors
    warnings += port_warnings

    return errors, warnings

def to_port(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None

def get_internal_port(app_data):
    # Same default as application_info.py: the HTTP port plus 10000, unless set (or set to null)
    if "internal_port" in app_data:
        return to_port(app_data["internal_port"])
    http_port = to_port(app_data.get("http_port"))
    return http_port + 10000 if http_port != None else None

def get_public_ports(app_data):
    ports = [app_data.get("http_port"), app_data.get("https_port")] + list(app_data.get("extra_ports") or [])
    return [to_port(p) for p in ports if to_port(p) != None]

def load_all_apps():
    apps = {}
    try:
        with open(os.path.join(REPO_DIR, BUILTIN_APPS_FILE)) as f:
            for app in json.load(f):
                apps[app["short_name"]] = app
    except (IOError, ValueError, KeyError):
        pass
    if os.path.isdir(APPS_DIR):
        for name in os.listdir(APPS_DIR):
            try:
                with open(os.path.join(APPS_DIR, name, name + ".json")) as f:
                    apps[name] = json.load(f)
            except (IOError, ValueError):
                pass
    return apps

def find_docker_publishes(app_dir):
    # Every port mapping a service, script or compose file publishes, as (file, mapping)
    found = []
    for root, dirs, files in os.walk(app_dir):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            if not name.endswith((".service", ".sh", ".yml", ".yaml")):
                continue
            path = os.path.join(root, name)
            try:
                with open(path) as f:
                    lines = f.read().split("\n")
            except (UnicodeDecodeError, IOError):
                continue
            for line in lines:
                if line.lstrip().startswith("#"):
                    continue
                for m in re.finditer(r'(?:--publish|-p)[ =]["\']?' + PORT_MAPPING, line):
                    found.append((os.path.relpath(path, app_dir), m.group(1)))
                if name.endswith((".yml", ".yaml")):
                    m = re.match(r'\s*-\s*["\']?' + PORT_MAPPING + r'["\']?\s*$', line)
                    if m:
                        found.append((os.path.relpath(path, app_dir), m.group(1)))
    return found

def check_app_ports(short_name, app_dir, app_data):
    # The app listens on 127.0.0.1:<internal_port> and nginx serves its public ports
    # (see Ports in doc/applications.md)
    errors = []
    warnings = []
    internal_port = get_internal_port(app_data)
    public_ports = get_public_ports(app_data)

    for path, mapping in find_docker_publishes(app_dir):
        parts = mapping.split("/")[0].split(":")
        if len(parts) == 2:
            errors.append("{} publishes port {} on all interfaces; publish it on 127.0.0.1:{}".format(path, parts[0], internal_port))
        elif parts[0] != "127.0.0.1":
            errors.append("{} publishes port {} on {}; publish it on 127.0.0.1".format(path, parts[1], parts[0]))
        elif internal_port == None:
            errors.append("{} publishes 127.0.0.1:{} but internal_port is not set".format(path, parts[1]))
        elif int(parts[1]) != internal_port:
            errors.append("{} publishes 127.0.0.1:{} but internal_port is {}".format(path, parts[1], internal_port))

    nginx_file = "nginx/https_{}.conf".format(short_name)
    try:
        with open(os.path.join(app_dir, nginx_file)) as f:
            nginx_conf = f.read()
    except IOError:
        nginx_conf = ""
    nginx_ports = [int(p) for p in re.findall(r'^\s*listen\s+(?:\S+:)?(\d+)', nginx_conf, re.M)]
    for port in nginx_ports:
        if port not in public_ports:
            errors.append("{} listens on {}, which is not http_port, https_port or in extra_ports".format(nginx_file, port))
    # Ports of every other app
    other_apps_ports = {}
    for name, other in load_all_apps().items():
        if name != short_name:
            other_internal = get_internal_port(other)
            other_apps_ports[name] = set(get_public_ports(other) + ([other_internal] if other_internal != None else []))

    for port in sorted(set(re.findall(r'proxy_pass\s+https?://(?:127\.0\.0\.1|localhost):(\d+)', nginx_conf))):
        # Apps without an internal port, nginx proxying to its own server blocks, and routes to
        # another app's ports (an API the app depends on) are fine
        port = int(port)
        if internal_port == None or port == internal_port or port in nginx_ports:
            continue
        if any(port in ports for ports in other_apps_ports.values()):
            continue
        warnings.append("{} proxies to port {}, not internal_port {}".format(nginx_file, port, internal_port))

    # No port may be used by another app
    own_ports = set(public_ports + ([internal_port] if internal_port != None else []))
    for name, ports in sorted(other_apps_ports.items()):
        for port in sorted(own_ports & ports):
            errors.append("Port {} is also used by {}".format(port, name))

    return errors, warnings

def get_marketplace_docker_images(short_name):
    # The app's (pin variable, image, tag with {VERSION}) entries in MARKETPLACE_DOCKER_IMAGES
    with open(os.path.join(REPO_DIR, HASHES_SCRIPT)) as f:
        m = re.search(r'^MARKETPLACE_DOCKER_IMAGES="([^"]*)"', f.read(), re.M)
    images = []
    for line in (m.group(1).split("\n") if m else []):
        parts = line.split()
        if len(parts) == 4 and parts[0] == short_name:
            images.append(parts[1:])
    return images

def app_downloads_source(app_data):
    return not app_data.get("download_skip", False) and app_data.get("download_type", "source") == "source"

def check_doc():
    # Every setting an app can put in its JSON file should be in the doc's settings table.
    # Settings are the fields application_info.py defaults with 'if not "x" in app', plus any
    # it reads with app_data.get(). Fields it always overwrites are not settings.
    with open(os.path.join(REPO_DIR, APP_INFO_FILE)) as f:
        app_info_src = f.read()
    with open(os.path.join(REPO_DIR, APP_DOC_FILE)) as f:
        doc_src = f.read()

    code_fields = set(re.findall(r'if not "([a-z_0-9]+)" in app', app_info_src))
    code_fields |= set(re.findall(r'app_data\.get\("([a-z_0-9]+)"', app_info_src))
    code_fields -= set(RUNTIME_FIELDS)
    doc_fields = set(re.findall(r'^\| <sub>([a-z_0-9]+)\s', doc_src, re.M))

    errors = []
    for field in sorted(code_fields - doc_fields):
        errors.append("{} is used by {} but is not in the {} settings table".format(field, APP_INFO_FILE, APP_DOC_FILE))
    for field in sorted(doc_fields - code_fields - set(DOC_ONLY_FIELDS)):
        # Documented settings that are read somewhere else in application_info.py are fine
        if '"{}"'.format(field) not in app_info_src:
            errors.append("{} is in the {} settings table but is not used by {}".format(field, APP_DOC_FILE, APP_INFO_FILE))

    for e in errors:
        print("Error: " + e)
    if errors:
        print("")
        print("Update the settings table in {}, or add the field to RUNTIME_FIELDS".format(APP_DOC_FILE))
        print("or DOC_ONLY_FIELDS in {} if it is not an app setting.".format(os.path.relpath(os.path.abspath(__file__), REPO_DIR)))
        exit(1)
    print("{} documents all {} app settings.".format(APP_DOC_FILE, len(doc_fields)))

def print_check_results(errors, warnings):
    for w in warnings:
        print("Warning: " + w)
    for e in errors:
        print("Error: " + e)


######################################################################################
## Commands
######################################################################################
def add_to_hashes_script(short_name):
    # Add app to MARKETPLACE_APPS so its source download hash is printed
    script = os.path.join(REPO_DIR, HASHES_SCRIPT)
    with open(script) as f:
        lines = f.read().split("\n")
    for i, line in enumerate(lines):
        if line.startswith('MARKETPLACE_APPS="'):
            apps = line[len('MARKETPLACE_APPS="'):].rstrip('"').split()
            if short_name not in apps:
                lines[i] = 'MARKETPLACE_APPS="{}"'.format(" ".join(sorted(apps + [short_name])))
                with open(script, "w") as f:
                    f.write("\n".join(lines))
            return True
    return False

def create():
    # Prompt for data
    full_app_name = prompt_string("Enter the application name (Ex. BTCPay Server)")
    short_name = generate_short_name(full_app_name)
    short_name = prompt_string("Enter the application identifier", short_name)
    app_dir = os.path.join(APPS_DIR, short_name)

    if os.path.exists(app_dir):
        print("App {} already exists. Exiting.".format(short_name))
        exit(1)

    # Copy the template
    shutil.copytree(TEMPLATE_DIR, app_dir)

    # Replace sampleapp with shortname
    app_json_file = "{}/sampleapp.json".format(app_dir)
    service_file = app_dir + "/sampleapp.service"
    update_app_info(app_json_file, "name", full_app_name)
    update_app_info(app_json_file, "app_tile_name", full_app_name)
    update_app_info(app_json_file, "linux_user", short_name)    # Matches User= in the service file
    replace_string_in_file(app_dir+"/www/python/sampleapp.py",      "sampleapp", short_name)
    replace_string_in_file(app_dir+"/nginx/https_sampleapp.conf",   "sampleapp", short_name)
    replace_string_in_file(service_file,                            "sampleapp", short_name)
    replace_string_in_file(app_dir+"/sampleapp.json",               "sampleapp", short_name)
    replace_string_in_file(app_dir+"/scripts/install_sampleapp.sh", "sampleapp", short_name)

    # Is this a service?
    is_service = prompt_yes_no("Is this application a service (can be enabled/disabled and not a cli tool)?")
    if not is_service:
        os.remove(service_file)
        update_app_info(app_json_file, "hide_status_icon", True)
        update_app_info(app_json_file, "can_enable_disable", False)

    # Process application (is it a web app?)
    if prompt_yes_no("Does this application have a web-based user interface?"):
        # nginx serves the HTTP and HTTPS ports; the app itself listens on localhost at the
        # HTTP port plus 10000 (see Ports in doc/applications.md)
        while True:
            http_port = prompt_integer("Enter the HTTP port for the application?")
            if http_port + 10000 <= 65535:
                break
            print("The HTTP port must be 55535 or lower, so the app's localhost port (HTTP port plus 10000) is valid.")
        https_port = prompt_integer("Enter the HTTPS port for the application?", (http_port+1))
        local_port = http_port + 10000
        update_app_info(app_json_file, "http_port", http_port)
        update_app_info(app_json_file, "https_port", https_port)
        # Replace 18000 first: it contains 8000
        for path in [app_dir+"/nginx/https_sampleapp.conf", service_file]:
            if os.path.isfile(path):
                replace_string_in_file(path, "18000", "LOCAL_PORT_PLACEHOLDER")
                replace_string_in_file(path, "8000", http_port)
                replace_string_in_file(path, "8001", https_port)
                replace_string_in_file(path, "LOCAL_PORT_PLACEHOLDER", local_port)
        print("The app must listen on 127.0.0.1:{} (a Docker app publishes it there).".format(local_port))
    else:
        # Remove web template items
        os.remove(app_dir+"/nginx/https_sampleapp.conf")
        update_app_info(app_json_file, "http_port", None)
        update_app_info(app_json_file, "https_port", None)
        update_app_info(app_json_file, "app_page_show_open_button", False)

    # Process application (does it depend on Bitcoin / Lightning?)
    wait_scripts = []
    if prompt_yes_no("Does this application depend on an active Lightning wallet?"):
        update_app_info(app_json_file, "requires_bitcoin", True)
        update_app_info(app_json_file, "requires_lightning", True)
        update_app_info(app_json_file, "category", "lightning_app")
        wait_scripts += ["wait_on_bitcoin.sh", "wait_on_lnd.sh"]
    else:
        update_app_info(app_json_file, "requires_lightning", False)
        if prompt_yes_no("Does this application depend on Bitcoin?", default_val="y"):
            update_app_info(app_json_file, "requires_bitcoin", True)
            update_app_info(app_json_file, "category", "bitcoin_app")
            wait_scripts += ["wait_on_bitcoin.sh"]
        else:
            update_app_info(app_json_file, "requires_bitcoin", False)
            update_app_info(app_json_file, "category", "uncategorized")

    # Process application (does it depend on docker?)
    uses_docker = prompt_yes_no("Does this application depend on Docker?", default_val="n")
    if uses_docker:
        # Docker apps pull a pinned image in their install script instead of downloading source
        update_app_info(app_json_file, "requires_docker_image_installation", True)
        update_app_info(app_json_file, "download_skip", True)
        update_app_info(app_json_file, "download_source_url", "not_required")
        remove_app_info(app_json_file, "download_source_sha256")
        wait_scripts += ["wait_on_docker_image_install.sh"]
    else:
        update_app_info(app_json_file, "requires_docker_image_installation", False)

    # Process application (does it depend on electrum server?)
    if prompt_yes_no("Does this application depend on Electrum Server?", default_val="n"):
        update_app_info(app_json_file, "requires_electrs", True)
        wait_scripts += ["wait_on_electrs.sh"]
    else:
        update_app_info(app_json_file, "requires_electrs", False)

    # Wait on dependencies before the app starts
    if os.path.exists(service_file):
        for script in wait_scripts:
            replace_string_in_file(service_file, "#ExecStartPre=/usr/bin/"+script, "ExecStartPre=/usr/bin/"+script)

    # Finally, rename files for app (makes them easier to search for when many apps are loaded)
    rename_files = [
        "www/python/sampleapp.py",
        "www/templates/sampleapp.html",
        "nginx/https_sampleapp.conf",
        "scripts/pre_sampleapp.sh",
        "scripts/post_sampleapp.sh",
        "scripts/uninstall_sampleapp.sh",
        "scripts/install_sampleapp.sh",
        "sampleapp.json",
        "sampleapp.service",
        "sampleapp.png",
    ]
    for orig_name in rename_files:
        new_name = orig_name.replace("sampleapp", short_name)
        old_path = os.path.join(app_dir, orig_name)
        new_path = os.path.join(app_dir, new_name)
        if os.path.exists(old_path):
            os.rename(old_path, new_path)

    with open("{}/{}.json".format(app_dir, short_name)) as f:
        downloads_source = app_downloads_source(json.load(f))
    added_to_hashes = downloads_source and add_to_hashes_script(short_name)

    # Done
    print("")
    print("Application created!")
    print("  Available at: {}".format(os.path.relpath(app_dir, REPO_DIR)))
    print("")
    print("Next steps:")
    print(" - Review and update the app data file: {}.json".format(short_name))
    print(" - Update the install script: scripts/install_{}.sh".format(short_name))
    if is_service:
        print(" - Update the service file: {}.service".format(short_name))
    print(" - Update the app icon: {}.png".format(short_name))
    print(" - Add app screenshots in the screenshots folder")
    if added_to_hashes:
        print(" - Added {} to MARKETPLACE_APPS in {}".format(short_name, HASHES_SCRIPT))
    if uses_docker:
        print(" - Add your image to MARKETPLACE_DOCKER_IMAGES in {}".format(HASHES_SCRIPT))
    if downloads_source or uses_docker:
        print(" - Pin your download: run {} {}".format(HASHES_SCRIPT, short_name))
        print("   and paste the printed value into your app's JSON or install script")
    print(" - Check your app: app_sdk/create.py check {}".format(short_name))
    print(" - Test it on a device (see doc/applications.md)")

def check(short_name):
    errors, warnings = check_app(short_name)
    print_check_results(errors, warnings)
    if errors:
        exit(1)
    if not warnings:
        print("{} looks good!".format(short_name))

def push(short_name, device, user, reinstall):
    errors, warnings = check_app(short_name)
    # A source download whose pin does not match latest_version fails to install on the device
    pin_warnings = [w for w in warnings if w.startswith("download_source_sha256")]
    print_check_results(errors + pin_warnings, [w for w in warnings if w not in pin_warnings])
    if errors or pin_warnings:
        exit(1)

    app_dir = os.path.join(APPS_DIR, short_name)
    target = "{}@{}".format(user, device)
    tmp_dir = "/tmp/mynode_app_push"

    print("Copying {} to {}...".format(short_name, device))
    sys.stdout.flush()
    subprocess.check_call(["ssh", target, "rm -rf {0} && mkdir -p {0}".format(tmp_dir)])
    subprocess.check_call(["rsync", "-a", "--delete", "--exclude", "__pycache__", "--exclude", ".DS_Store",
                           app_dir + "/", "{}:{}/{}/".format(target, tmp_dir, short_name)])

    # Replace the app folder (removing deleted files), load it, then install or upgrade it.
    # Apps pushed to a device that did not have them can be removed again from the Marketplace.
    # install only reinstalls when latest_version changed, so script changes need --reinstall.
    script = """
set -e
APP={app}
DST=/usr/share/mynode_apps/$APP
[ -d $DST ] || touch {tmp}/$APP/is_manually_added
mkdir -p $DST
rsync -a --delete --exclude is_manually_added {tmp}/$APP/ $DST/
[ -f {tmp}/$APP/is_manually_added ] && mv {tmp}/$APP/is_manually_added $DST/
chown -R root:root $DST
rm -rf {tmp}
mynode-manage-apps init
mynode-manage-apps {install} $APP
if [ -f $DST/nginx/https_$APP.conf ]; then nginx -t && systemctl reload nginx; fi
systemctl restart www
if systemctl is-active --quiet $APP; then systemctl restart $APP; fi
echo "Pushed $APP"
""".format(app=short_name, tmp=tmp_dir, install="reinstall" if reinstall else "install")
    # A terminal lets sudo ask for the password
    tty = ["-t"] if sys.stdin.isatty() else []
    subprocess.check_call(["ssh"] + tty + [target, "sudo bash -c " + shlex.quote(script)])

def main():
    parser = ArgumentParser(description="Create a new MyNode application")
    subparsers = parser.add_subparsers(dest="command")
    subparsers.add_parser("create", help="Create new application (default)")
    parser_check = subparsers.add_parser("check", help="Check an application")
    parser_check.add_argument("app", help="App to check")
    subparsers.add_parser("check_doc", help="Check the settings table in doc/applications.md")
    parser_push = subparsers.add_parser("push", help="Copy an application to a device and install it")
    parser_push.add_argument("app", help="App to push")
    parser_push.add_argument("device", help="Device IP address or hostname")
    parser_push.add_argument("--user", default="admin", help="SSH user (default: admin)")
    parser_push.add_argument("--reinstall", action="store_true", help="Reinstall even if the version did not change")
    args = parser.parse_args()

    if args.command == "check":
        check(args.app)
    elif args.command == "check_doc":
        check_doc()
    elif args.command == "push":
        try:
            push(args.app, args.device, args.user, args.reinstall)
        except subprocess.CalledProcessError:
            print("Push failed")
            exit(1)
    else:
        create()

if __name__ == "__main__":
    main()
