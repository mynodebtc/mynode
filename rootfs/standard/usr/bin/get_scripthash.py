#!/usr/bin/env python3
from bitcointx.wallet import *
import hashlib
import sys

if len(sys.argv) != 2:
    print("Usage: get_scripthash.py <addr>")
    exit(1)

addr = CBitcoinAddress( sys.argv[1] )
script = addr.to_scriptPubKey()
script_hash = hashlib.sha256(script).hexdigest()
print(script_hash)