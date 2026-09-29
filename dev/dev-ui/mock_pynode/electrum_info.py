"""Mock shim for pynode/electrum_info.py.

Patches `requests` inside the real module with a fake that serves prometheus
metrics text, so the REAL update_electrs_info() runs unchanged: it parses the
metrics, tracks the index height against the bitcoin block height and sets
electrs_active itself."""
from _mockutil import load_real, export, fixture, real

_real = load_real("electrum_info")


class _FakeMetricsResponse(object):
    @property
    def text(self):
        height = real("bitcoin_info").bitcoin_block_height
        return ("# HELP electrs_index_height Electrs index height\n"
                "# TYPE electrs_index_height gauge\n"
                "electrs_index_height {}\n".format(height))


class _FakeRequests(object):
    def get(self, url, timeout=None):
        return _FakeMetricsResponse()


def get_electrs_version():
    return fixture("device.json")["electrs_version"]


def get_electrs_db_size(is_testnet=False):
    return "97G"


def get_from_electrum(method, params=[]):
    return {"id": 0, "result": "(mocked electrum response)"}


_real.requests = _FakeRequests()
_real.get_electrs_version = get_electrs_version
_real.get_electrs_db_size = get_electrs_db_size
_real.get_from_electrum = get_from_electrum

export(globals(), _real)
