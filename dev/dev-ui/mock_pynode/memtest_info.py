"""Mock shim for pynode/memtest_info.py.

The container is not an amd64 device with GRUB, so support is forced on and update-grub does nothing.
The real code reads and writes its state in /home/bitcoin/.mynode/memtest.json (and the drive copy),
so a result can be faked by writing that file; see dev/dev-ui/README.md."""
from _mockutil import load_real, export

_real = load_real("memtest_info")


def is_memtest_supported():
    return True


def run_update_grub():
    return True


def get_memtest_machine_id():
    return "devui0000000000"


def is_memtester_installed():
    return True


_real.is_memtest_supported = is_memtest_supported
_real.run_update_grub = run_update_grub
_real.get_memtest_machine_id = get_memtest_machine_id
_real.is_memtester_installed = is_memtester_installed
_real.MEMTEST_GRUB_FILE = "/tmp/mock_state/mynode-memtest.cfg"
_real.BADRAM_GRUB_FILE = "/tmp/mock_state/mynode-badram.cfg"

export(globals(), _real)
