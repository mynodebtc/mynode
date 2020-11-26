#!/usr/bin/python
import requests
from tabulate import tabulate
import json

apps = [{"name": "bitcoin/bitcoin",                         "current_version": "v0.20.1"},
        {"name": "lightningnetwork/lnd",                    "current_version": "v0.11.1-beta"},
        {"name": "lightninglabs/loop",                      "current_version": "v0.9.0-beta"},
        {"name": "romanz/electrs",                          "current_version": "v0.8.5"},
        {"name": "Ride-The-Lightning/RTL",                  "current_version": "v0.9.3"},
        {"name": "janoside/btc-rpc-explorer",               "current_version": "v2.0.2"},
        {"name": "BlueWallet/LndHub",                       "current_version": "v1.2.0"},
        {"name": "btcpayserver/btcpayserver",               "current_version": "v1.0.5.9"},
        {"name": "unchained-capital/caravan",               "current_version": "v0.3.3"},
        {"name": "cryptoadvance/specter-desktop",           "current_version": "v0.9.2"},
        {"name": "lnbits/lnbits",                           "current_version": "6cf4881"},
        {"name": "apotdevin/thunderhub",                    "current_version": "v0.10.1"}
]
apps = [{"name": "bitcoin/bitcoin",                         "current_version_variable": "BTC_VERSION"},
        {"name": "lightningnetwork/lnd",                    "current_version_variable": "LND_VERSION"},
        {"name": "lightninglabs/loop",                      "current_version_variable": "LOOP_VERSION"},
        {"name": "lightninglabs/pool",                      "current_version_variable": "POOL_VERSION"},
        {"name": "romanz/electrs",                          "current_version":          "v0.8.5"},
        {"name": "Ride-The-Lightning/RTL",                  "current_version_variable": "RTL_VERSION"},
        {"name": "janoside/btc-rpc-explorer",               "current_version_variable": "BTCRPCEXPLORER_VERSION"},
        {"name": "BlueWallet/LndHub",                       "current_version_variable": "LNDHUB_VERSION"},
        {"name": "btcpayserver/btcpayserver",               "current_version":          "v1.0.5.9"},
        {"name": "unchained-capital/caravan",               "current_version_variable": "CARAVAN_VERSION"},
        {"name": "cryptoadvance/specter-desktop",           "current_version_variable": "SPECTER_VERSION"},
        {"name": "lnbits/lnbits",                           "current_version":          "6cf4881"},
        {"name": "apotdevin/thunderhub",                    "current_version_variable": "THUNDERHUB_VERSION"}
]

# Apps that don't work or are not on GitHub
#  - Samourai Whirlpool 
#  - Samourai Dojo
#  - 

def needs_update(current, latest):
    # Remove "v" since some variables are inconsistent in v1.2.3 vs 1.2.3
    c = current.replace("v","")
    l = latest.replace("v","")
    if c != l:
        return "X"
    return ""

def get_current_version_from_variable(version_variable):
    try:
        with open("../rootfs/standard/usr/share/mynode/mynode_app_versions.sh", "r") as f:
            lines = f.readlines()
            for line in lines:
                if version_variable in line:
                    parts = line.split("=")
                    version = parts[1]
                    version = version.replace("\"","").strip()
                    return version
    except:
        return "UNKNOWN FAIL"
    return "UNKNOWN " + version_variable

def check_app_versions():
    data=[]
    for app in apps:
        # Lookup current version from mynode_app_version.sh file
        current_version = "UNKNOWN"
        if "current_version_variable" in app:
            current_version = get_current_version_from_variable(app["current_version_variable"])
        else:
            current_version = app["current_version"]

        # Get data from github
        github_url = "https://api.github.com/repos/" + app["name"] + "/releases/latest"
        github_tag_url = "https://api.github.com/repos/" + app["name"] + "/tags"
        row=[]
        try:
            r = requests.get(github_url)
            j = r.json()
            latest_version = j["tag_name"]
            need_update = needs_update(current_version, latest_version)
            row = [app["name"], current_version, latest_version, need_update]
        except:
            #print(str(e))
            #print(r.content)
            try:
                r = requests.get(github_tag_url)
                j = r.json()
                latest_version = j[0]["name"]
                need_update = needs_update(current_version, latest_version)
                row=[app["name"], current_version, latest_version, need_update]
            except Exception as e:
                row=[app["name"], current_version, "FAILED", "?"]
                #print(str(e))
                #print(r.content)
        data.append(row)

    table = tabulate(data, headers=['App', 'myNode Version', 'Latest Version', 'Needs Update'], tablefmt='pretty')
    print(table)

if __name__ == "__main__":
    check_app_versions()
