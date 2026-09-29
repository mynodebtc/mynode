"""Mock shim for pynode/bitcoin_info.py.

Instead of overriding the update functions, this replaces AuthServiceProxy
(the bitcoind JSON-RPC client) with a fixture-backed fake, so the REAL
update_bitcoin_main_info()/update_bitcoin_other_info() code runs unchanged -
including its data formatting, caching and wallet handling. The sync state is
driven by the /tmp/mock_state/bitcoin.json knob (dev panel)."""
import hashlib
import time
import urllib.parse

from _mockutil import load_real, export, fixture, get_knob

_real = load_real("bitcoin_info")


def _sync_view():
    """Compute (headers, blocks, verificationprogress) from fixture + knob."""
    info = fixture("bitcoin.json")["blockchain_info"]
    headers = int(info["headers"])
    knob = get_knob("bitcoin", {"behind_blocks": 0})
    behind = int(knob.get("behind_blocks", 0))
    blocks = max(0, headers - behind)
    if behind <= 0:
        progress = 0.9999999
    elif knob.get("progress") is not None:
        progress = float(knob["progress"])
    else:
        progress = float(blocks) / headers
    return headers, blocks, progress


def _fake_block_hash(height):
    return "0000000000000000000" + hashlib.sha256(str(height).encode()).hexdigest()[:45]


class FakeAuthServiceProxy(object):
    """Duck-typed stand-in for bitcoinrpc.authproxy.AuthServiceProxy."""

    _hash_to_height = {}

    def __init__(self, service_url, timeout=None):
        self._wallet = None
        if "/wallet/" in service_url:
            self._wallet = urllib.parse.unquote(service_url.rsplit("/wallet/", 1)[1])

    def getblockchaininfo(self):
        info = fixture("bitcoin.json")["blockchain_info"]
        headers, blocks, progress = _sync_view()
        info["blocks"] = blocks
        info["verificationprogress"] = progress
        info["bestblockhash"] = _fake_block_hash(blocks)
        return info

    def getblockhash(self, height):
        block_hash = _fake_block_hash(height)
        FakeAuthServiceProxy._hash_to_height[block_hash] = height
        return block_hash

    def getblock(self, block_hash):
        height = FakeAuthServiceProxy._hash_to_height.get(block_hash, 0)
        headers, blocks, _ = _sync_view()
        # Deterministic-ish per-height values so the UI looks alive
        seed = int(hashlib.sha256(str(height).encode()).hexdigest()[:8], 16)
        return {
            "hash": block_hash,
            "confirmations": max(1, blocks - height + 1),
            "height": height,
            "version": 0x20000000,
            "merkleroot": _fake_block_hash(height + 1000000)[4:],
            "time": int(time.time()) - (blocks - height) * 600,
            "mediantime": int(time.time()) - (blocks - height) * 600 - 1800,
            "nonce": seed,
            "bits": "17034219",
            "difficulty": None,  # stripped by the API anyway (JSON float issue)
            "nTx": 1500 + seed % 2500,
            "size": 1400000 + seed % 500000,
            "weight": 3900000 + seed % 90000,
            "tx": [],
            "previousblockhash": _fake_block_hash(height - 1),
        }

    def getpeerinfo(self):
        return fixture("bitcoin.json")["peers"]

    def getnetworkinfo(self):
        return fixture("bitcoin.json")["network_info"]

    def getmempoolinfo(self):
        return fixture("bitcoin.json")["mempool_info"]

    def listwallets(self):
        return list(fixture("bitcoin.json")["wallets"].keys())

    def getwalletinfo(self):
        wallets = fixture("bitcoin.json")["wallets"]
        return wallets.get(self._wallet, next(iter(wallets.values())))


class _FakeFeeResponse(object):
    def json(self):
        return fixture("bitcoin.json")["recommended_fees"]


class _FakeRequests(object):
    """bitcoin_info only uses requests for the local mempool fee API."""

    def get(self, url, timeout=None):
        return _FakeFeeResponse()


def get_bitcoin_version():
    return fixture("device.json")["bitcoin_version"]


def run_bitcoincli_command(cmd):
    # Route through the fake bitcoin-cli binary for canned output
    try:
        import subprocess
        return _real.to_string(subprocess.check_output(
            "bitcoin-cli " + cmd, stderr=subprocess.STDOUT, shell=True))
    except Exception as e:
        return str(e)


_real.AuthServiceProxy = FakeAuthServiceProxy
_real.requests = _FakeRequests()
_real.get_bitcoin_version = get_bitcoin_version
_real.run_bitcoincli_command = run_bitcoincli_command

export(globals(), _real)
