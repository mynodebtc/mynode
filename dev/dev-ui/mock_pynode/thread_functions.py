"""Mock shim for www/mynode/thread_functions.py (shadows the www module).

The thread wrapper functions stay real (they call the already-mocked update
functions). Overridden: the 5-second-blocking CPU sampler, the external
public-IP lookup and the dmesg follower."""
import time

import psutil

from _mockutil import load_real, export, fixture

_real = load_real("thread_functions")


def update_device_info():
    try:
        _real.reload_throttled_data()
        _real.cpu_usage = "{:.1f}%".format(psutil.cpu_percent(interval=0.2))
        if _real.os_drive_usage_details == "...":
            _real.os_drive_usage_details = (
                "<small><b>App Storage</b><br/><pre>2.1G	/opt/mynode/ (mocked)</pre><br/>"
                "<b>User Storage</b><br/><pre>350M	/home/ (mocked)</pre></small>")
            _real.data_drive_usage_details = (
                "<small><b>Disk Format</b><p>ext4</p><b>Data Storage</b><br/>"
                "<pre>689G	/mnt/hdd/mynode/ (mocked)</pre></small>")
    except Exception as e:
        _real.log_message("[mock] update_device_info: {}".format(e))


def find_public_ip():
    _real.public_ip = fixture("device.json")["public_ip"]


def monitor_dmesg():
    # Nothing to monitor in the container; sleep forever so the thread wrapper
    # (if enabled via DEV_REAL_THREADS) doesn't spin.
    while True:
        time.sleep(3600)


_real.update_device_info = update_device_info
_real.find_public_ip = find_public_ip
_real.monitor_dmesg = monitor_dmesg

export(globals(), _real)
