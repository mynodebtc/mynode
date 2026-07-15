"""Mock shim for pynode/drive_info.py.

/mnt/hdd is a real tmpfs mount in the container, so the mount checks and size
queries work naturally. Only the usage percentages are overridden - they come
from the /tmp/mock_state/drive.json knob so the dev panel can push the UI into
the low-disk-space error paths (>= 95%)."""
from _mockutil import load_real, export, get_knob

_real = load_real("drive_info")

_DEFAULTS = {"data": "61%", "os": "34%"}


def get_data_drive_usage():
    return get_knob("drive", _DEFAULTS).get("data", "61%")


def get_os_drive_usage():
    return get_knob("drive", _DEFAULTS).get("os", "34%")


def get_mynode_drive_size():
    return 1863  # ~2TB drive, in GB like the real function returns


_real.get_data_drive_usage = get_data_drive_usage
_real.get_os_drive_usage = get_os_drive_usage
_real.get_mynode_drive_size = get_mynode_drive_size

export(globals(), _real)
