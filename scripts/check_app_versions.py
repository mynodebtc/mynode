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
        {"name": "btcpayserver/btcpayserver",               "current_version": "v1.0.5.5"},
        {"name": "unchained-capital/caravan",               "current_version": "v0.3.3"},
        {"name": "cryptoadvance/specter-desktop",           "current_version": "v0.9.2"},
        {"name": "lnbits/lnbits",                           "current_version": "6cf4881"},
        {"name": "apotdevin/thunderhub",                    "current_version": "v0.10.1"}
]

# Apps that don't work or are not on GitHub
#  - Samourai Whirlpool 
#  - Samourai Dojo
#  - 

def needs_update(current, latest):
    if current != latest:
        return "X"
    return ""


def check_app_versions():
    data=[]
    for app in apps:
        # Get data from github
        github_url = "https://api.github.com/repos/" + app["name"] + "/releases/latest"
        github_tag_url = "https://api.github.com/repos/" + app["name"] + "/tags"
        row=[]
        current_version = app["current_version"]
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
