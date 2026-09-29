"""Mock shim for pynode/lightning_info.py.

Overrides the two REST chokepoints (lnd_get / lnd_get_v2) with fixture-backed
lookups so the real update_lightning_info() populates all module globals
through the genuine code paths. LND "readiness" is driven by the
/tmp/mock_state/lnd.json knob."""
import hashlib
import time

from _mockutil import load_real, export, fixture, get_knob

_real = load_real("lightning_info")

_ALIAS_WORDS = [
    "SatoshiRelay", "ThunderNode", "LightningLlama", "BoltBeacon",
    "ZapZeppelin", "PlasmaPeer", "VoltViking", "AmpereApe",
]


def _now_ts(offset):
    """Fixture timestamps are stored as negative offsets from 'now'."""
    return str(int(time.time()) + int(offset))


def _resolve_offsets(obj):
    """Recursively convert negative time offsets to absolute timestamps."""
    time_keys = ("time_stamp", "creation_date", "settle_date", "best_header_timestamp")
    if isinstance(obj, dict):
        for k, v in list(obj.items()):
            if k in time_keys and isinstance(v, (int, float)) and v <= 0:
                obj[k] = _now_ts(v)
            else:
                _resolve_offsets(v)
    elif isinstance(obj, list):
        for item in obj:
            _resolve_offsets(item)
    return obj


def _lnd_ready_knob():
    return bool(get_knob("lnd", {"ready": True}).get("ready", True))


def lnd_get(path, timeout=10, params={}):
    if path.startswith("/graph/node/"):
        pubkey = path.rsplit("/", 1)[1]
        idx = int(hashlib.sha256(pubkey.encode()).hexdigest()[:4], 16)
        return {"node": {"alias": _ALIAS_WORDS[idx % len(_ALIAS_WORDS)], "pub_key": pubkey}}

    data = fixture("lightning.json").get("/v1" + path)
    if data is None:
        return {"error": "no fixture for /v1" + path}
    if path == "/getinfo":
        data["synced_to_chain"] = _lnd_ready_knob()
        data["block_height"] = _real.bitcoin_block_height
    return _resolve_offsets(data)


def lnd_get_v2(path, timeout=10):
    path = path.split("?", 1)[0]  # fixture keys have no query strings
    data = fixture("lightning.json").get("/v2" + path)
    if data is None:
        return {"error": "no fixture for /v2" + path}
    return _resolve_offsets(data)


def get_macaroon():
    return "0201036C6E6402F801030A10MOCK"


def gen_new_wallet_seed():
    return ("mock abandon ability able about above absent absorb abstract "
            "absurd abuse access accident account accuse achieve acid acoustic "
            "acquire across act action actor")


def get_lnd_version():
    return "v" + fixture("device.json")["lnd_version"]


def get_loop_version():
    return "v" + fixture("device.json")["loop_version"]


def get_pool_version():
    return "v" + fixture("device.json")["pool_version"]


def get_lit_version():
    return "v" + fixture("device.json")["lit_version"]


def lnd_get_channel_db_size():
    return "142M"


def restart_lnd_actual():
    # Brief visual blip: LND drops out and comes back a few seconds later
    _real.lnd_ready = False
    import threading

    def _back():
        time.sleep(4)
        _real.lnd_ready = _lnd_ready_knob()

    threading.Thread(target=_back, daemon=True).start()


def is_lnd_logged_in():
    return _lnd_ready_knob()


def create_wallet(seed):
    _real.log_message("[mock] create_wallet called")
    _real.touch(_real.get_lightning_wallet_file())
    time.sleep(1)
    return True


_real.lnd_get = lnd_get
_real.lnd_get_v2 = lnd_get_v2
_real.get_macaroon = get_macaroon
_real.gen_new_wallet_seed = gen_new_wallet_seed
_real.get_lnd_version = get_lnd_version
_real.get_loop_version = get_loop_version
_real.get_pool_version = get_pool_version
_real.get_lit_version = get_lit_version
_real.lnd_get_channel_db_size = lnd_get_channel_db_size
_real.restart_lnd_actual = restart_lnd_actual
_real.is_lnd_logged_in = is_lnd_logged_in
_real.create_wallet = create_wallet

export(globals(), _real)
