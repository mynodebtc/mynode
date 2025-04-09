#!/usr/bin/python3
import requests
from tabulate import tabulate
import argparse
import json
import re

priority_apps = [\
    {"name": "bitcoin/bitcoin",                         "current_version_variable": "BTC_VERSION"},
    {"name": "lightningnetwork/lnd",                    "current_version_variable": "LND_VERSION"},
    {"name": "lightninglabs/loop",                      "current_version_variable": "LOOP_VERSION"},
    {"name": "lightninglabs/pool",                      "current_version_variable": "POOL_VERSION"},
    {"name": "lightninglabs/lightning-terminal",        "current_version_variable": "LIT_VERSION"},
    {"name": "mempool/mempool",                         "current_version_variable": "MEMPOOL_VERSION"},
    {"name": "Ride-The-Lightning/RTL",                  "current_version_variable": "RTL_VERSION"},
    {"name": "janoside/btc-rpc-explorer",               "current_version_variable": "BTCRPCEXPLORER_VERSION"},
    {"name": "btcpayserver/btcpayserver",               "current_version_variable": "BTCPAYSERVER_VERSION"},
    {"name": "lnbits/lnbits",                           "current_version_variable": "LNBITS_VERSION"},
    {"name": "apotdevin/thunderhub",                    "current_version_variable": "THUNDERHUB_VERSION"},
    {"name": "openoms/joininbox",                       "current_version_variable": "JOININBOX_VERSION"},
    {"name": "joinmarket-webui/jam",                    "dynamic_app_name":         "jam"},
    {"name": "OCEAN-xyz/datum_gateway",                 "dynamic_app_name":         "datum"},
]
other_apps = [\
    {"name": "lightninglabs/chantools",                 "current_version_variable": "CHANTOOLS_VERSION"},
    {"name": "romanz/electrs",                          "current_version_variable": "ELECTRS_VERSION"},
    {"name": "BlueWallet/LndHub",                       "current_version_variable": "LNDHUB_VERSION"},
    {"name": "unchained-capital/caravan",               "current_version_variable": "CARAVAN_VERSION"},
    {"name": "cryptoadvance/specter-desktop",           "current_version_variable": "SPECTER_VERSION"},
    {"name": "Coldcard/ckbunker",                       "current_version_variable": "CKBUNKER_VERSION"},
    {"name": "alexbosworth/balanceofsatoshis",          "current_version_variable": "BOS_VERSION"},
    {"name": "bitromortac/lndmanage",                   "current_version_variable": "LNDMANAGE_VERSION"},
    {"name": "pxsocs/warden_terminal",                  "current_version":          "64e5db1"},
    {"name": "stakwork/sphinx-relay",                   "current_version_variable": "SPHINXRELAY_VERSION"},
    #{"name": "whirlpool/whirlpool-client-cli",          "current_version_variable": "WHIRLPOOL_VERSION"}, # REMOVED
    {"name": "dojo/samourai-dojo",                      "current_version_variable": "DOJO_VERSION"},
    #{"name": "JoinMarket-Org/joinmarket-clientserver",  "current_version_variable": "JOINMARKET_VERSION"}, # Old, now use within joininbox
    {"name": "curly60e/pyblock",                        "current_version_variable": "PYBLOCK_VERSION"},
    {"name": "cryptosharks131/lndg",                    "dynamic_app_name":         "lndg"},
    {"name": "Lily-Technologies/lily-wallet",           "dynamic_app_name":         "lilywallet"},
    {"name": "edouardparis/lntop",                      "dynamic_app_name":         "lntop"},
    {"name": "monlovesmango/astral",                    "dynamic_app_name":         "astral"},
    {"name": "fiatjaf/noscl",                           "dynamic_app_name":         "noscl"},
    {"name": "scsibug/nostr-rs-relay",                  "dynamic_app_name":         "nostrrsrelay"},
    {"name": "getalby/hub",                             "dynamic_app_name":         "albyhub"},
]

# Apps that don't work or are not on GitHub
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

def get_current_version_from_dynamic_app(app_name):
    try:
        filename = "../rootfs/standard/usr/share/mynode_apps/{}/{}.json".format(app_name, app_name)
        with open(filename, "r") as f:
            json_data = json.load(f)
            if "latest_version" in json_data:
                return json_data["latest_version"]
    except:
        return "UNKNOWN FAIL 1"
    return "UNKNOWN FAIL 2"

def get_app_version_data(app_name, current_version):
    success = False
    github_url = "https://api.github.com/repos/" + app_name + "/releases/latest"
    github_tag_url = "https://api.github.com/repos/" + app_name + "/tags"
    row=[app_name, current_version, "FAILED", "?"]

    # Try GitHub Releases
    try:
        r = requests.get(github_url)
        j = r.json()
        latest_version = j["tag_name"]
        need_update = needs_update(current_version, latest_version)
        row = [app_name, current_version, latest_version, need_update]
        success = True
    except:
        pass
    
    # Try GitHub Tags
    if not success:
        try:
            r = requests.get(github_tag_url)
            j = r.json()
            latest_version = j[0]["name"]
            need_update = needs_update(current_version, latest_version)
            row=[app_name, current_version, latest_version, need_update]
            success = True
        except Exception as e:
            pass
            #print(str(e))
            #print(r.content)

    # Try Samourai Whirlpool CLI
    if (not success and ("whirlpool" in app_name or "dojo" in app_name)):
        try:
            samourai_url = "https://code.samourai.io/"+app_name+"/-/tags?format=atom"
            r = requests.get(samourai_url)
            matches = re.search( r'/-/tags/(.*?)</id>', str(r.content), re.M)
            latest_version = matches.group(1)
            need_update = needs_update(current_version, latest_version)
            row=[app_name, current_version, latest_version, need_update]
            success = True
        except Exception as e:
            #print(str(e))
            pass


    return row

def get_app_version_data_list(apps):
    data=[]
    for app in apps:
        # Lookup current version from mynode_app_version.sh file
        current_version = "UNKNOWN"
        if "current_version_variable" in app:
            current_version = get_current_version_from_variable(app["current_version_variable"])
        elif "dynamic_app_name" in app:
            current_version = get_current_version_from_dynamic_app(app["dynamic_app_name"])
        else:
            current_version = app["current_version"]

        # Get data from github
        row = get_app_version_data(app["name"], current_version)
        data.append(row)
    return data

def check_app_versions(include_all_apps):
    data = get_app_version_data_list(priority_apps)
    table = tabulate(data, headers=['Priority App', 'MyNode Version', 'Latest Version', 'Needs Update'], tablefmt='pretty')
    print(table)

    if include_all_apps:
        data = get_app_version_data_list(other_apps)
        table = tabulate(data, headers=['App', 'MyNode Version', 'Latest Version', 'Needs Update'], tablefmt='pretty')
        print(table)
    else:
        print("\n\n***Skipping optional apps. Include with '-a'.***\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(prog='check_app_versions.py', description="This script checks for new versions of MyNode applications")
    parser.add_argument('-a', '--allapps', action='store_true')
    args = parser.parse_args()

    check_app_versions(include_all_apps=args.allapps)
