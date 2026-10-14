#!/usr/bin/env python3
"""Check MyNode application versions against their upstream releases.

Apps are found automatically:
  - built-in apps: every <APP>_VERSION in mynode_app_versions.sh
  - marketplace apps: every rootfs/standard/usr/share/mynode_apps/<app>/<app>.json

The upstream GitHub repo and tag prefix are taken from the download URLs in the rootfs scripts
(or the app's download_source_url). Apps installed another way (Docker image, npm, apt) are
listed in the override tables below. An app with no known source is reported as UNTRACKED,
so a new app shows up here until it gets a source.

Uses the GitHub token from $GITHUB_TOKEN or "gh auth token" when available (the anonymous
API limit is 60 requests an hour). Standard library only.
"""
import argparse
import glob
import json
import os
import re
import ssl
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOTFS = os.path.join(REPO_ROOT, "rootfs", "standard")
VERSIONS_FILE = os.path.join(ROOTFS, "usr/share/mynode/mynode_app_versions.sh")
APP_INFO_FILE = os.path.join(ROOTFS, "usr/share/mynode/application_info.json")
MARKETPLACE_DIR = os.path.join(ROOTFS, "usr/share/mynode_apps")

# Built-in apps whose source is not a GitHub download URL in the rootfs scripts.
# Keys are the <APP> in <APP>_VERSION. Sources: {"github": repo, "prefix": tag prefix} or {"npm": package}
BUILTIN_SOURCES = {
    "BTC":          {"github": "bitcoin/bitcoin"},
    "ELECTRS":      {"github": "romanz/electrs"},
    "LNBITS":       {"github": "lnbits/lnbits"},
    "BTCPAYSERVER": {"github": "btcpayserver/btcpayserver"},
    "SPECTER":      {"github": "cryptoadvance/specter-desktop"},
    "LNDMANAGE":    {"github": "bitromortac/lndmanage"},
    "CKBUNKER":     {"github": "Coldcard/ckbunker"},
    "NETDATA":      {"github": "netdata/netdata"},
    "JOINMARKET":   {"github": "JoinMarket-Org/joinmarket-clientserver"},
    "DOJO":         {"github": "Dojo-Open-Source-Project/samourai-dojo"},
    "BOS":          {"npm": "balanceofsatoshis"},
}

# Short names for <APP>_VERSION variables that have no get_app_version line
BUILTIN_SHORT_NAMES = {"ELECTRS": "electrs", "LOG2RAM": "log2ram", "JOINMARKET": "joinmarket"}

# Toolchains and libraries, not apps. Shown with --deps.
DEPENDENCIES = {"PYTHON", "PYTHON_PIP", "PYTHON_SETUPTOOLS", "PYTHON_WHEEL", "APP_PYTHON",
                "APP_PYTHON_MINOR", "UV", "NODE_JS", "RUST", "GO", "TOR_SOURCE"}

# Marketplace apps whose source is not a GitHub download_source_url or a github.com URL in their scripts
MARKETPLACE_SOURCES = {
    "albyhub":   {"github": "getalby/hub"},
    "canary":    {"github": "schjonhaug/canary"},
    "jam":       {"github": "joinmarket-webui/jam"},
    "tailscale": {"github": "tailscale/tailscale"},
}

COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
GITHUB_URL_RE = re.compile(r"github\.com/([\w.-]+)/([\w.-]+?)(?:\.git)?/")
PRERELEASE_RE = re.compile(r"(rc|alpha|beta|pre|dev)\.?\d*$", re.I)


# ---------------------------------------------------------------------------
# Upstream lookups

def get_github_token():
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    try:
        return subprocess.run(["gh", "auth", "token"], capture_output=True, text=True,
                              timeout=10).stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None

GITHUB_TOKEN = None

def make_ssl_context():
    # python.org builds on macOS ship without CA certificates
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        pass
    if not os.path.exists(ssl.get_default_verify_paths().openssl_cafile or "") and os.path.exists("/etc/ssl/cert.pem"):
        return ssl.create_default_context(cafile="/etc/ssl/cert.pem")
    return ssl.create_default_context()

SSL_CONTEXT = make_ssl_context()

class UpstreamError(Exception):
    pass

def fetch_json(url, github=False):
    headers = {"User-Agent": "mynode-check-app-versions"}
    if github:
        headers["Accept"] = "application/vnd.github+json"
        if GITHUB_TOKEN:
            headers["Authorization"] = "Bearer " + GITHUB_TOKEN
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30,
                                    context=SSL_CONTEXT) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        if e.code in (403, 429):
            raise UpstreamError("rate limited (HTTP {}), set GITHUB_TOKEN".format(e.code))
        raise UpstreamError("HTTP {}".format(e.code))
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise UpstreamError(str(e))

def version_key(v):
    return tuple(int(n) for n in re.findall(r"\d+", v))

def latest_github_version(repo, prefix):
    """Latest release tag with the given prefix, or the highest matching tag if there is no release."""
    release = fetch_json("https://api.github.com/repos/{}/releases/latest".format(repo), github=True)
    if release and release.get("tag_name", "").startswith(prefix):
        return release["tag_name"]
    tags = fetch_json("https://api.github.com/repos/{}/tags?per_page=100".format(repo), github=True)
    if tags is None:
        raise UpstreamError("repo not found")
    names = [t["name"] for t in tags if t["name"].startswith(prefix)]
    stable = [n for n in names if not PRERELEASE_RE.search(n[len(prefix):])]
    candidates = stable or names
    if not candidates:
        if release:
            return release["tag_name"]
        raise UpstreamError("no releases or tags")
    return max(candidates, key=lambda n: version_key(n[len(prefix):]))

def latest_binary_release(repo, prefix, asset_templates):
    """Newest stable release that has binaries, with notes on newer releases MyNode cannot install.

    asset_templates are the release file names MyNode downloads, with {VERSION} for the version
    and * for other variables (like the architecture)."""
    releases = fetch_json("https://api.github.com/repos/{}/releases?per_page=30".format(repo), github=True)
    if releases is None:
        raise UpstreamError("repo not found")
    releases = [r for r in releases if not r["draft"] and not r["prerelease"]
                and r["tag_name"].startswith(prefix)]
    releases.sort(key=lambda r: version_key(r["tag_name"][len(prefix):]), reverse=True)
    notes = []
    for r in releases:
        tag = r["tag_name"]
        if not r["assets"]:
            notes.append("{} has no binaries".format(tag))
            continue
        names = [a["name"] for a in r["assets"]]
        def present(template):
            pattern = re.escape(template.replace("{VERSION}", tag)).replace(r"\*", ".*")
            return any(re.fullmatch(pattern, n) for n in names)
        files = [t.replace("{VERSION}", tag) for t in asset_templates]
        sigs = [f for t, f in zip(asset_templates, files) if t.endswith(".sig")]
        missing = [f for t, f in zip(asset_templates, files) if not t.endswith(".sig") and not present(t)]
        if sigs and not any(present(t) for t in asset_templates if t.endswith(".sig")):
            missing.append(" or ".join(sigs))
        if missing:
            notes.append("{} lacks {}".format(tag, ", ".join(missing)))
        return tag, notes
    raise UpstreamError("no release with binaries" + (" ({})".format("; ".join(notes)) if notes else ""))

def commits_behind(repo, commit):
    info = fetch_json("https://api.github.com/repos/{}".format(repo), github=True)
    if info is None:
        raise UpstreamError("repo not found")
    branch = info["default_branch"]
    cmp = fetch_json("https://api.github.com/repos/{}/compare/{}...{}".format(repo, commit, branch),
                     github=True)
    if cmp is None:
        raise UpstreamError("commit {} not found".format(commit[:10]))
    date = cmp["commits"][-1]["commit"]["committer"]["date"][:10] if cmp["commits"] else ""
    return cmp["ahead_by"], date

def latest_npm_version(package):
    data = fetch_json("https://registry.npmjs.org/{}/latest".format(package))
    if data is None:
        raise UpstreamError("package not found")
    return data["version"]


# ---------------------------------------------------------------------------
# Reading MyNode's pins

def describe_condition(if_line):
    parts = []
    if re.search(r'IS_32_BIT"?\s*=\s*"?1', if_line):
        parts.append("32-bit")
    for n in re.findall(r'DEBIAN_VERSION"?\s+-lt\s+"?(\d+)', if_line):
        parts.append("Debian < " + n)
    return " or ".join(parts) or if_line.strip()

def read_builtin_pins():
    """Return {APP: {version, short_name, old_pins, comment, commit, line}} from mynode_app_versions.sh."""
    apps = {}
    condition = None
    with open(VERSIONS_FILE) as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        if re.match(r"\s*if\s", line):
            condition = describe_condition(line)
        elif re.match(r"\s*fi\b", line):
            condition = None
        m = re.match(r'^(\s*)([A-Z0-9_]+)_VERSION="?([^"\s$]+)"?\s*(?:#\s*(.*))?$', line)
        if m:
            indent, name, version, comment = m.groups()
            if indent and name in apps:
                apps[name]["old_pins"].append((condition, version, comment or ""))
            elif not indent and name not in apps:
                apps[name] = {"version": version, "short_name": None, "old_pins": [],
                              "comment": comment or "", "commit": None, "line": i + 1}
            continue
        m = re.match(r'^([A-Z0-9_]+)_VERSION=\$\(get_app_version "\$\w+" "([\w-]+)"\)', line)
        if m and m.group(1) in apps:
            apps[m.group(1)]["short_name"] = m.group(2)
        # MyNode builds pinned to an upstream commit, like CKBUNKER_UPGRADE_URL
        m = re.match(r'^([A-Z0-9_]+)_UPGRADE_URL=\S*github\.com/\S+/archive/([0-9a-f]{40})\.', line)
        if m and m.group(1) in apps:
            apps[m.group(1)]["commit"] = m.group(2)
    for name, app in apps.items():
        if not app["short_name"]:
            app["short_name"] = BUILTIN_SHORT_NAMES.get(name, name.lower())
    return apps

def find_builtin_download_urls():
    """Map APP -> {repo, prefix, commented, assets} from GitHub URLs using $APP_VERSION in rootfs scripts.

    commented is True when the URLs only appear in comments. assets are the release file names
    downloaded from releases/download/, as templates for latest_binary_release()."""
    found = {}
    url_re = re.compile(r"https?://github\.com/([\w.-]+)/([\w.-]+)/(\S*?)\$\{?([A-Z0-9_]+)_VERSION\}?")
    asset_re = re.compile(r"https?://github\.com/[\w.-]+/[\w.-]+/releases/download/"
                          r"\$\{?([A-Z0-9_]+)_VERSION\}?/([^/\s\"']+)")
    for path in glob.glob(os.path.join(ROOTFS, "**", "*.sh"), recursive=True):
        try:
            with open(path, errors="replace") as f:
                lines = f.readlines()
        except OSError:
            continue
        for line in lines:
            commented = line.lstrip().startswith("#")
            for owner, repo, between, name in url_re.findall(line):
                # Tag prefix is the text in the same path segment before the version, e.g. caravan-
                prefix = between.rsplit("/", 1)[-1]
                prev = found.get(name)
                if prev is None or (prev["commented"] and not commented):
                    found[name] = {"repo": owner + "/" + repo, "prefix": prefix, "commented": commented,
                                   "assets": []}
            if not commented:
                for name, asset in asset_re.findall(line):
                    template = asset.replace("${}_VERSION".format(name), "{VERSION}")
                    template = template.replace("${{{}_VERSION}}".format(name), "{VERSION}")
                    template = re.sub(r"\$\{?\w+\}?", "*", template)
                    if name in found and template not in found[name]["assets"]:
                        found[name]["assets"].append(template)
    return found

def read_app_info():
    try:
        with open(APP_INFO_FILE) as f:
            return {a["short_name"]: a for a in json.load(f) if "short_name" in a}
    except (OSError, ValueError):
        return {}

def check_venv_pin(app):
    """Versions marked 'must match usr/share/mynode/venvs/<x>.in' must appear there as ==<version>."""
    m = re.search(r"(usr/share/mynode/venvs/[\w.-]+\.in)", app["comment"])
    if not m:
        return None
    path = os.path.join(ROOTFS, m.group(1))
    try:
        with open(path) as f:
            text = f.read()
    except OSError:
        return "missing " + m.group(1)
    if not re.search(r"==\s*v?{}\b".format(re.escape(app["version"].lstrip("v"))), text):
        return "does not match " + os.path.basename(path)
    return None


# ---------------------------------------------------------------------------
# Building the report

def compare(current, latest, prefix):
    c = current.lstrip("vV")
    l = (latest[len(prefix):] if prefix and latest.startswith(prefix) else latest).lstrip("vV")
    if c == l:
        return "current", latest
    if version_key(l) > version_key(c):
        return "UPDATE", latest
    return "check", latest

def lookup(row):
    """Fill in row["latest"] and row["status"] from the row's source."""
    src = row["source"]
    try:
        if row["commit"]:
            behind, date = commits_behind(src["github"], row["commit"])
            row["latest"] = "HEAD {}".format(date) if behind else "HEAD"
            row["status"] = "UPDATE ({} commits)".format(behind) if behind else "current"
        elif "npm" in src:
            row["status"], row["latest"] = compare(row["version"], latest_npm_version(src["npm"]), "")
        else:
            prefix = src.get("prefix", "")
            if src.get("assets"):
                latest, notes = latest_binary_release(src["github"], prefix, src["assets"])
                row["notes"] = notes + row["notes"]
            else:
                latest, notes = latest_github_version(src["github"], prefix), []
            row["status"], row["latest"] = compare(row["version"], latest, prefix)
            if notes and row["status"] == "current":
                row["status"] = "current (newer release not installable)"
    except UpstreamError as e:
        row["latest"], row["status"] = "?", "ERROR: " + str(e)
    return row

def source_label(src):
    return "npm:" + src["npm"] if "npm" in src else src["github"]

def builtin_rows(include_deps):
    pins = read_builtin_pins()
    urls = find_builtin_download_urls()
    app_info = read_app_info()
    rows, skipped, untracked = [], [], []
    for name, app in pins.items():
        info = app_info.get(app["short_name"], {})
        label = info.get("name") or app["short_name"]
        is_dep = name in DEPENDENCIES
        if is_dep and not include_deps:
            continue
        if info.get("is_deprecated"):
            skipped.append("{} (deprecated)".format(label))
            continue
        src = BUILTIN_SOURCES.get(name)
        if not src and name in urls:
            if urls[name]["commented"]:
                skipped.append("{} (install commented out)".format(label))
                continue
            src = {"github": urls[name]["repo"], "prefix": urls[name]["prefix"],
                   "assets": urls[name]["assets"]}
        if not src:
            if not is_dep:
                untracked.append("{}_VERSION (line {})".format(name, app["line"]))
            continue
        commit = app["commit"] or (app["version"] if COMMIT_RE.match(app["version"]) else None)
        notes = []
        mismatch = check_venv_pin(app)
        if mismatch:
            notes.append("PIN MISMATCH: " + mismatch)
        if app["commit"]:
            notes.append("MyNode build {} of upstream commit {}".format(app["version"], app["commit"][:10]))
        for condition, version, comment in app["old_pins"]:
            notes.append("{}: {}".format(condition, version) + (" ({})".format(comment) if comment else ""))
        rows.append({"name": label, "version": app["version"], "source": src, "commit": commit,
                     "notes": notes, "dep": is_dep, "short_name": app["short_name"]})
    # Two apps can share a display name (JoinInBox and JoinMarket are both "JoinMarket")
    names = [r["name"].lower() for r in rows]
    for r in rows:
        if names.count(r["name"].lower()) > 1:
            r["name"] += " ({})".format(r["short_name"])
    return rows, skipped, untracked

def marketplace_rows():
    rows, skipped, untracked = [], [], []
    for path in sorted(glob.glob(os.path.join(MARKETPLACE_DIR, "*", "*.json"))):
        short_name = os.path.basename(os.path.dirname(path))
        if os.path.basename(path) != short_name + ".json":
            continue
        with open(path) as f:
            app = json.load(f)
        label = app.get("name", short_name)
        if app.get("show_on_marketplace_page") is False and app.get("can_reinstall") is False:
            skipped.append("{} (removed)".format(label))
            continue
        if app.get("is_deprecated"):
            skipped.append("{} (deprecated)".format(label))
            continue
        version = app.get("latest_version", "")
        src = MARKETPLACE_SOURCES.get(short_name)
        if not src:
            m = re.match(r"https://github\.com/([\w.-]+/[\w.-]+)/archive/(?:refs/tags/)?(.*?)\{VERSION\}",
                         app.get("download_source_url", ""))
            if m and "FILL_IN" not in m.group(1):
                src = {"github": m.group(1), "prefix": m.group(2)}
        if not src:
            # e.g. "go install github.com/<owner>/<repo>@$VERSION" in the install script
            for script in sorted(glob.glob(os.path.join(os.path.dirname(path), "scripts", "*.sh"))):
                with open(script, errors="replace") as f:
                    m = GITHUB_URL_RE.search(f.read().replace("@", "/"))
                if m:
                    src = {"github": m.group(1) + "/" + m.group(2)}
                    break
        if not src:
            untracked.append("{} ({})".format(label, os.path.relpath(path, REPO_ROOT)))
            continue
        rows.append({"name": label, "version": version, "source": src,
                     "commit": version if COMMIT_RE.match(version) else None, "notes": [], "dep": False})
    return rows, skipped, untracked


def print_table(title, rows):
    headers = ["App", "MyNode", "Latest", "Status", "Source", "Notes"]
    table = [[r["name"], r["version"][:10] if r["version"] == r["commit"] else r["version"],
              r["latest"], r["status"], source_label(r["source"]), "; ".join(r["notes"])] for r in rows]
    widths = [max([len(h)] + [len(t[i]) for t in table]) for i, h in enumerate(headers)]
    print("\n" + title)
    print("  ".join(h.ljust(w) for h, w in zip(headers, widths)).rstrip())
    print("  ".join("-" * w for w in widths))
    for t in table:
        print("  ".join(c.ljust(w) for c, w in zip(t, widths)).rstrip())

def main():
    global GITHUB_TOKEN
    parser = argparse.ArgumentParser(description="Check MyNode application versions against upstream releases")
    parser.add_argument("-u", "--updates", action="store_true", help="only list apps that need attention")
    parser.add_argument("-d", "--deps", action="store_true", help="also check toolchains and libraries")
    args = parser.parse_args()

    GITHUB_TOKEN = get_github_token()
    if not GITHUB_TOKEN:
        print("No GitHub token (GITHUB_TOKEN or gh auth login); anonymous limit is 60 requests an hour",
              file=sys.stderr)

    b_rows, b_skipped, b_untracked = builtin_rows(args.deps)
    m_rows, m_skipped, m_untracked = marketplace_rows()
    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lookup, b_rows + m_rows))

    def keep(r):
        return not args.updates or r["status"] != "current" or any("MISMATCH" in n for n in r["notes"])

    sections = [("Built-in apps", [r for r in b_rows if not r["dep"]]), ("Marketplace apps", m_rows)]
    if args.deps:
        sections.append(("Dependencies", [r for r in b_rows if r["dep"]]))
    for title, rows in sections:
        rows = sorted(filter(keep, rows), key=lambda r: (r["status"] == "current", r["name"].lower()))
        if rows:
            print_table(title, rows)

    untracked = b_untracked + m_untracked
    if untracked:
        print("\nUNTRACKED (no upstream source; add one to the tables in scripts/check_app_versions.py):")
        for u in untracked:
            print("  " + u)
    if b_skipped or m_skipped:
        print("\nSkipped: " + ", ".join(b_skipped + m_skipped))

    errors = [r for r in b_rows + m_rows if r["status"].startswith("ERROR")]
    return 1 if errors or untracked else 0

if __name__ == "__main__":
    sys.exit(main())
