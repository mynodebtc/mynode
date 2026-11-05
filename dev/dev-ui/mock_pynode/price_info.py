"""Mock shim for www/mynode/price_info.py (shadows the www module).

Replaces the `torify curl blockchain.info` price fetch with a random walk
around the fixture price, and seeds 24h of history so the ticker/delta UI has
data immediately. All getters stay real."""
import random
import time

from _mockutil import load_real, export, fixture

_real = load_real("price_info")


def _seed_history():
    if _real.price_data:
        return
    base = float(fixture("price.json")["start_price"])
    now = int(time.time())
    rng = random.Random(42)
    price = base
    points = []
    for i in range(288):  # 24h of 5-minute samples
        price = max(1000.0, price + rng.uniform(-120, 130))
        points.append({"time": now - (288 - i) * 300, "price": round(price, 2)})
    _real.price_data.extend(points)


def update_price_info():
    if not _real.get_ui_setting("price_ticker"):
        return
    _seed_history()
    last = _real.price_data[-1]["price"] if _real.price_data else float(fixture("price.json")["start_price"])
    now = int(time.time())
    _real.price_data.append({"time": now, "price": round(max(1000.0, last + random.uniform(-120, 130)), 2)})
    while _real.price_data and _real.price_data[0]["time"] < now - 24 * 60 * 60:
        _real.price_data.pop(0)


_seed_history()
_real.update_price_info = update_price_info

export(globals(), _real)
