from flask import Blueprint, render_template, session, abort, Markup, request, redirect
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
from pprint import pprint, pformat
import json
import time
import subprocess

mynode_bitcoin_cli = Blueprint('mynode_bitcoin_cli',__name__)

### Helper functions
def runcmd(cmd):
    cmd = "bitcoin-cli --conf=/home/admin/.bitcoin/bitcoin.conf --datadir=/mnt/hdd/mynode/bitcoin "+cmd+"; exit 0"
    try:
        results = subprocess.check_output(cmd, stderr=subprocess.STDOUT, shell=True)
    except Exception as e:
        results = str(e)
    return results
    
@mynode_bitcoin_cli.route("/bitcoin-cli/run", methods=['POST'])
def runcmd_page():
    if not request:
        return ""
    response = runcmd(request.form['cmd'])
    return response


### Page functions
@mynode_bitcoin_cli.route("/bitcoin-cli")
def bitcoincli():
    # Load page
    templateData = {
        "title": "myNode Bitcoin CLI"
    }
    return render_template('bitcoin_cli.html', **templateData)
