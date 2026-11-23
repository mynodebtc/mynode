from utilities import *
import hashlib
import json
import os
import re
import select
import struct
import subprocess
import time

# Memory tests (amd64 only). Bad 4K pages they find are remembered and get a memmap= boot option each,
# so Linux never uses them again, also after a reflash (the list is kept on the OS and data drives).
# Bad pages are only ever added, until they are cleared (after the RAM is replaced).
#
# Two tests feed the list:
#  - Boot test (setting): every boot runs the kernel's built-in test (memtest=17), which writes and reads
#    back test patterns over free RAM before anything else uses it. Startup reads the result from the
#    kernel log. It is quick, but each pattern is written and read only once, so it misses weak cells.
#  - Manual test: boots into a test mode where startup pauses before any service starts, and runs
#    memtester for a chosen time. memtester only reports offsets in its own buffer, so the physical
#    page is looked up in /proc/<pid>/pagemap while it runs (its buffer is locked in RAM).

MEMTEST_PATTERNS = 17
MEMTEST_SECONDS_PER_GB_PER_PATTERN = 0.27   # Measured on an Intel N150 with 16 GB: 17 patterns in ~73 s
MEMTEST_BOOT_SETTING = "memtest_at_boot"
MEMTEST_GRUB_FILE = "/etc/default/grub.d/mynode-memtest.cfg"
BADRAM_GRUB_FILE = "/etc/default/grub.d/mynode-badram.cfg"
MEMTEST_STATE_FILES = ["/home/bitcoin/.mynode/memtest.json", "/mnt/hdd/mynode/settings/memtest.json"]
MEMTEST_MAX_BAD_PAGES = 64      # The kernel command line is limited to 2048 characters on x86
MEMTEST_MAX_RUNS = 10
PAGE_SIZE = 4096

MEMTESTER = "/usr/sbin/memtester"
MANUAL_MARKER_FILE = "/home/bitcoin/.mynode/memtest_manual_passes"    # OS drive only: one test, this unit
MANUAL_PROGRESS_FILE = "/run/mynode/memtest_progress.json"
MANUAL_STOP_FILE = "/run/mynode/memtest_stop"
MANUAL_PASSES = [1, 2, 4]
MANUAL_MAX_HOURS = 24                   # In case memtester stops making progress
MANUAL_RESERVE_MB = 768                 # Left free for the web UI and the rest of the OS while testing
MANUAL_MAX_FAILURES = 10000             # Stop looking up addresses after this many failure lines
MANUAL_KEPT_FAILURE_LINES = 20          # memtester's first failure lines, kept with the result
MEMORY_TEST_STATUS = "memory_test"      # Home page state while the manual test runs

# Kernel log lines from mm/memtest.c, for example
#   early_memtest: # of tests: 17
#     dddddddddddddddd bad mem addr 0x000000046a7a7c48 - 0x000000046a7a7c50 reserved
MEMTEST_COUNT_RE = re.compile(r"early_memtest: # of tests: (\d+)")
MEMTEST_BAD_RE = re.compile(r"bad mem addr (?:0x)?([0-9a-fA-F]+) - (?:0x)?([0-9a-fA-F]+) reserved")

# memtester output
MEMTESTER_GOT_RE = re.compile(r"got\s+\d+MB \((\d+) bytes\)")

# memtester's tests in the order it runs them, with how many times each one sweeps the whole buffer
# (memtester 4.6, tests.c) and how many steps its progress counter shows. memtester also clears the
# buffer after each test (about half a sweep). The sweep counts are what the time estimate is based on.
MEMTESTER_TESTS = [
    ("Stuck Address", 32, 16),
    ("Random Value", 3.5, 1),
    ("Compare XOR", 3.5, 1),
    ("Compare SUB", 3.5, 1),
    ("Compare MUL", 3.5, 1),
    ("Compare DIV", 5.5, 1),
    ("Compare OR", 3.5, 1),
    ("Compare AND", 3.5, 1),
    ("Sequential Increment", 2.5, 1),
    ("Solid Bits", 128.5, 64),
    ("Block Sequential", 512.5, 256),
    ("Checkerboard", 128.5, 64),
    ("Bit Spread", 256.5, 128),
    ("Bit Flip", 1024.5, 512),
    ("Walking Ones", 256.5, 128),
    ("Walking Zeroes", 256.5, 128),
    ("8-bit Writes", 90.5, 2),       # One byte (or two) per store: measured about 2 minutes each
    ("16-bit Writes", 60.5, 2),      # on 14 GB, much slower per sweep than whole-word tests
]
MEMTESTER_TEST_NAMES = [t[0] for t in MEMTESTER_TESTS]
MEMTESTER_PASS_SWEEPS = sum(t[1] for t in MEMTESTER_TESTS)
MEMTESTER_MEASURE_SWEEPS = 40               # Enough done to estimate the speed from this run
MEMTESTER_SECONDS_PER_GB_SWEEP = 0.112      # Intel N150: one clean pass over 12.5 GB took 62 minutes
MEMTESTER_TOKEN_RE = re.compile(r"Loop (?P<loop>\d+)|(?P<test>" + "|".join(re.escape(n) for n in MEMTESTER_TEST_NAMES) +
                                r")\s*:|(?P<step>setting|testing)\s+(?P<n>\d+)|(?P<done>Done\.)")
MEMTESTER_STUCK_RE = re.compile(r"FAILURE: possible bad address line at offset 0x([0-9a-fA-F]+)")
MEMTESTER_COMPARE_RE = re.compile(r"FAILURE: 0x[0-9a-fA-F]+ != 0x[0-9a-fA-F]+ at offset 0x([0-9a-fA-F]+)")


def _log(msg):
    # Printed for the startup script's journal, and logged when the web UI has set up its logger
    print(msg, flush=True)
    log_message(msg)


#==================================
# Support and machine identity
#==================================
def is_memtest_supported():
    # The running kernel must have the test built in, and the device must boot with GRUB
    try:
        if os.uname().machine not in ["x86_64", "amd64"]:
            return False
        if not os.path.isfile("/usr/sbin/update-grub"):
            return False
        with open("/boot/config-{}".format(os.uname().release)) as f:
            return "CONFIG_MEMTEST=y" in f.read().split("\n")
    except Exception:
        return False

def is_memtester_installed():
    return os.path.isfile(MEMTESTER)

def _read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except Exception:
        return ""

def get_memtest_machine_id():
    # Bad pages belong to this machine's RAM, not to a drive, so saved pages are only used on the
    # machine that found them. Built from the board's identity and its built-in (PCI) network cards'
    # MAC addresses, so a USB network adapter does not change it.
    parts = [_read("/sys/class/dmi/id/product_uuid"), _read("/sys/class/dmi/id/board_serial")]
    try:
        for name in sorted(os.listdir("/sys/class/net")):
            subsystem = os.path.join("/sys/class/net", name, "device", "subsystem")
            if os.path.exists(subsystem) and os.path.basename(os.path.realpath(subsystem)) == "pci":
                parts.append(_read(os.path.join("/sys/class/net", name, "address")))
    except Exception:
        pass
    return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()[:16]

def get_ram_gb():
    try:
        with open("/proc/meminfo") as f:
            return int(f.readline().split()[1]) / (1024 * 1024)
    except Exception:
        return 0


#==================================
# Saved state
#==================================
def _empty_state(machine):
    return {"machine": machine, "bad_pages": [], "runs": [], "total_runs": 0}

def _state_files():
    from drive_info import is_mynode_drive_mounted
    files = [MEMTEST_STATE_FILES[0]]
    if is_mynode_drive_mounted():
        files.append(MEMTEST_STATE_FILES[1])
    return files

def load_memtest_state():
    # Merges the copies on the OS and data drives that were saved on this machine
    machine = get_memtest_machine_id()
    state = _empty_state(machine)
    pages = set()
    runs = {}
    total = 0
    rate = None
    for path in MEMTEST_STATE_FILES:
        try:
            with open(path) as f:
                saved = json.load(f)
        except Exception:
            continue
        if saved.get("machine") != machine:
            continue
        pages.update(int(p, 16) for p in saved.get("bad_pages", []))
        total = max(total, saved.get("total_runs", len(saved.get("runs", []))))
        rate = saved.get("seconds_per_gb_sweep") or rate
        for run in saved.get("runs", []):
            runs[run.get("time", 0)] = run
    state["bad_pages"] = ["0x{:x}".format(p) for p in sorted(pages)]
    state["runs"] = [runs[t] for t in sorted(runs)][-MEMTEST_MAX_RUNS:]
    state["total_runs"] = max(total, len(runs))
    if rate:
        state["seconds_per_gb_sweep"] = rate
    return state

def save_memtest_state(state):
    data = json.dumps(state, indent=2, sort_keys=True)
    for path in _state_files():
        try:
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                f.write(data)
            os.replace(tmp, path)
        except Exception as e:
            _log("Could not save memory test state to {}: {}".format(path, str(e)))

def _add_run(run, pages, seconds_per_gb_sweep=None):
    # Saves a test result. Returns the number of pages that were not known before.
    state = load_memtest_state()
    if seconds_per_gb_sweep:
        state["seconds_per_gb_sweep"] = seconds_per_gb_sweep
    known = set(int(p, 16) for p in state["bad_pages"])
    new_pages = [p for p in pages if p not in known]
    run["time"] = int(time.time())
    run["kernel"] = os.uname().release
    run["new_pages"] = len(new_pages)
    state["runs"] = (state["runs"] + [run])[-MEMTEST_MAX_RUNS:]
    state["total_runs"] = state.get("total_runs", 0) + 1
    known.update(pages)
    state["bad_pages"] = ["0x{:x}".format(p) for p in sorted(known)]
    save_memtest_state(state)
    return len(new_pages)


#==================================
# Parsing and boot options
#==================================
def parse_memtest_log(text):
    # Returns (number of patterns run or None, [(start, end), ...] bad ranges)
    m = MEMTEST_COUNT_RE.search(text)
    patterns = int(m.group(1)) if m else None
    ranges = [(int(a, 16), int(b, 16)) for a, b in MEMTEST_BAD_RE.findall(text)]
    return patterns, ranges

def ranges_to_pages(ranges):
    pages = set()
    for start, end in ranges:
        page = start - (start % PAGE_SIZE)
        while page < max(end, start + 1):
            pages.add(page)
            page += PAGE_SIZE
    return sorted(pages)

def get_memmap_args(pages):
    # Adjacent pages become one range: memmap=<size>K$<start> reserves it
    args = []
    run_start = None
    run_len = 0
    for page in sorted(pages):
        if run_start is not None and page == run_start + run_len * PAGE_SIZE:
            run_len += 1
            continue
        if run_start is not None:
            args.append("memmap={}K${}".format(run_len * PAGE_SIZE // 1024, hex(run_start)))
        run_start = page
        run_len = 1
    if run_start is not None:
        args.append("memmap={}K${}".format(run_len * PAGE_SIZE // 1024, hex(run_start)))
    return args

def _grub_file_content(comment, args):
    # The file is sourced by a shell, then copied into grub.cfg, where GRUB reads "\$" as "$".
    # So "$" is written as "\\\$" here.
    escaped = " ".join(a.replace("$", "\\\\\\$") for a in args)
    return "# {}\nGRUB_CMDLINE_LINUX=\"$GRUB_CMDLINE_LINUX {}\"\n".format(comment, escaped)

def _write_if_changed(path, content):
    # content None removes the file. Returns True if the file changed.
    old = None
    if os.path.isfile(path):
        old = _read(path) + "\n"
    if content is None:
        if old is None:
            return False
        os.remove(path)
        return True
    if old == content:
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)
    return True

def run_update_grub():
    try:
        subprocess.check_output(["/usr/sbin/update-grub"], stderr=subprocess.STDOUT)
        return True
    except Exception as e:
        _log("update-grub failed: {}".format(str(e)))
        return False

def write_badram_grub_file(pages):
    if not pages:
        return _write_if_changed(BADRAM_GRUB_FILE, None)
    content = _grub_file_content("Bad RAM pages found by MyNode's memory test. Managed by MyNode.",
                                 get_memmap_args(pages[:MEMTEST_MAX_BAD_PAGES]))
    return _write_if_changed(BADRAM_GRUB_FILE, content)


#==================================
# Boot test (setting)
#==================================
def is_boot_memtest_enabled():
    return settings_file_exists(MEMTEST_BOOT_SETTING)

def sync_boot_memtest_grub_file():
    # Keeps the memtest= boot option in line with the setting. Returns True if it changed.
    content = None
    if is_boot_memtest_enabled():
        content = _grub_file_content("Memory test at every boot. Managed by MyNode (Settings).",
                                     ["memtest={}".format(MEMTEST_PATTERNS)])
    return _write_if_changed(MEMTEST_GRUB_FILE, content)

def set_boot_memtest_enabled(enabled):
    if enabled:
        create_settings_file(MEMTEST_BOOT_SETTING)
    else:
        delete_settings_file(MEMTEST_BOOT_SETTING)
    if sync_boot_memtest_grub_file():
        return run_update_grub()
    return True

def get_boot_memtest_estimate_minutes():
    seconds = MEMTEST_PATTERNS * get_ram_gb() * MEMTEST_SECONDS_PER_GB_PER_PATTERN
    return max(1, int(round(seconds / 60.0)))

def _read_kernel_log():
    for cmd in [["dmesg"], ["journalctl", "-k", "-b", "--no-pager", "-o", "cat"]]:
        try:
            text = to_string(subprocess.check_output(cmd, stderr=subprocess.DEVNULL))
            if MEMTEST_COUNT_RE.search(text):
                return text
        except Exception:
            pass
    return ""

def collect_memtest_results():
    # At startup: if this boot ran the kernel test, save its result. Then keep the boot option in line
    # with the setting. Returns True if the GRUB files changed.
    cmdline = _read("/proc/cmdline")
    if re.search(r"(^|\s)memtest=\d+", cmdline):
        patterns, ranges = parse_memtest_log(_read_kernel_log())
        _add_run({"type": "boot",
                  "patterns": patterns,
                  "bad_ranges": ["{:#x}-{:#x}".format(a, b) for a, b in ranges]},
                 ranges_to_pages(ranges))
        _log("Memory test at boot: {} patterns, bad ranges: {}".format(patterns, ranges))
    return sync_boot_memtest_grub_file()

def apply_bad_ram_pages():
    # Keeps the memmap= and memtest= boot options up to date. Returns True if they changed.
    state = load_memtest_state()
    save_memtest_state(state)   # Copies the list to whichever drive is missing it
    pages = [int(p, 16) for p in state["bad_pages"]]
    changed = write_badram_grub_file(pages)
    if sync_boot_memtest_grub_file():   # The setting can come back from the data drive after a reflash
        changed = True
    return changed

def clear_bad_ram_pages():
    state = load_memtest_state()
    state["bad_pages"] = []
    state["runs"] = []
    state["total_runs"] = 0
    save_memtest_state(state)
    if write_badram_grub_file([]):
        run_update_grub()


#==================================
# Manual test (memtester)
#==================================
def schedule_manual_memtest(passes):
    # The test boot also runs the kernel's test, which covers memory memtester can't get: what the
    # kernel and early startup are using by the time memtester runs. Startup removes it again
    # unless the boot test setting is on.
    if passes not in MANUAL_PASSES:
        return False
    set_file_contents(MANUAL_MARKER_FILE, str(passes))
    os.sync()
    if not is_boot_memtest_enabled():
        content = _grub_file_content("Memory test on the next boot only. Removed by MyNode at startup.",
                                     ["memtest={}".format(MEMTEST_PATTERNS)])
        if _write_if_changed(MEMTEST_GRUB_FILE, content) and not run_update_grub():
            cancel_manual_memtest()
            _write_if_changed(MEMTEST_GRUB_FILE, None)
            return False
    return True

def get_manual_memtest_scheduled_passes():
    try:
        return int(_read(MANUAL_MARKER_FILE))
    except Exception:
        return 0

def cancel_manual_memtest():
    delete_file(MANUAL_MARKER_FILE)

def stop_manual_memtest():
    touch(MANUAL_STOP_FILE)

def get_manual_memtest_progress():
    try:
        with open(MANUAL_PROGRESS_FILE) as f:
            return json.load(f)
    except Exception:
        return None

def get_memory_test_seconds_this_boot():
    # How long a manual test held up startup on this boot (its progress file is in /run/mynode)
    progress = get_manual_memtest_progress()
    if not progress or "start" not in progress:
        return 0
    end = time.time() if progress.get("running") else progress.get("updated", progress["start"])
    return max(0, int(end - progress["start"]))

def get_manual_memtest_view():
    # Progress for the home page. The time left is counted down from the last update here, so the
    # browser's clock doesn't matter.
    progress = get_manual_memtest_progress()
    if not progress:
        return {"started": False}
    running = progress.get("running", False)
    remaining = 0
    if running:
        remaining = max(0, int(progress.get("remaining_seconds", 0) - (time.time() - progress.get("updated", time.time()))))
    return {
        "started": True,
        "running": running,
        "percent": progress.get("percent", 0) if running else 100,
        "remaining_seconds": remaining,
        "remaining_text": format_duration_left(remaining),
        "passes": progress.get("passes", 1),
        "pass": min(progress.get("pass", 1), progress.get("passes", 1)),
        "test": progress.get("test", ""),
        "tested_gb": round(progress.get("tested_mb", 0) / 1024.0, 1),
        "failures": progress.get("failures", 0),
        "new_pages": progress.get("new_pages", 0),
    }

def format_duration(seconds):
    minutes = max(1, int(round(seconds / 60.0)))
    if minutes < 60:
        return "{} min".format(minutes)
    hours, minutes = divmod(minutes, 60)
    if hours >= 3 or minutes == 0:
        # Rough enough at this length: round to the half hour
        half_hours = int(round((hours * 60 + minutes) / 30.0))
        return "{:g} hr".format(half_hours / 2.0)
    return "{} hr {} min".format(hours, minutes)

def format_duration_left(seconds):
    if seconds < 60:
        return "less than a minute left"
    return "about {} left".format(format_duration(seconds))

def _seconds_per_gb_sweep(state=None):
    state = state or load_memtest_state()
    return state.get("seconds_per_gb_sweep") or MEMTESTER_SECONDS_PER_GB_SWEEP

def _write_progress(progress):
    try:
        progress["updated"] = time.time()
        tmp = MANUAL_PROGRESS_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(progress, f)
        os.replace(tmp, MANUAL_PROGRESS_FILE)
    except Exception:
        pass

def _set_mynode_status(status):
    try:
        if status:
            with open("/run/mynode/.mynode_status", "w") as f:
                f.write(status)
        else:
            os.remove("/run/mynode/.mynode_status")
    except Exception:
        pass

def _anonymous_mappings(pid):
    # memtester's anonymous read/write mappings from /proc/<pid>/smaps: (start, end, locked bytes)
    mappings = []
    with open("/proc/{}/smaps".format(pid)) as f:
        for line in f:
            fields = line.split()
            if re.match(r"^[0-9a-f]+-[0-9a-f]+$", fields[0]):
                current = None
                if len(fields) == 5 and fields[1].startswith("rw"):
                    a, b = [int(x, 16) for x in fields[0].split("-")]
                    current = [a, b, 0]
                    mappings.append(current)
            elif fields[0] == "Locked:" and current is not None:
                current[2] = int(fields[1]) * 1024
    return mappings

def _find_memtester_buffer(pid, wantbytes):
    # memtester mallocs its buffer, and glibc serves a request this big with its own mapping: a 16 byte
    # header, then the buffer. memtester starts testing at the next page, and (memtester 4.6) subtracts
    # the bytes it skipped twice from the size. The first half is bufa, the second bufb.
    # memtester locks only the tested area, so the tested area starts where the big locked mapping does.
    # Returns (start of the tested area, start of bufb) or None.
    skipped = PAGE_SIZE - 16
    bufsize = wantbytes - 2 * skipped
    try:
        mappings = _anonymous_mappings(pid)
    except Exception as e:
        _log("Memory test: could not read memtester's memory map: {}".format(str(e)))
        return None
    locked = [m for m in mappings if m[1] - m[0] >= bufsize // 2 and m[2] >= (m[1] - m[0]) - PAGE_SIZE]
    # memtester locks before its second subtraction, so the locked length is the size minus one skip
    expected = (wantbytes - skipped + PAGE_SIZE - 1) // PAGE_SIZE * PAGE_SIZE
    if len(locked) == 1:
        aligned = locked[0][0]
        if locked[0][1] - aligned != expected:
            _log("Memory test: memtester's locked mapping is {:#x} bytes, expected {:#x}".format(locked[0][1] - aligned, expected))
        return aligned, aligned + bufsize // 2
    _log("Memory test: could not find memtester's buffer, addresses won't be known. Large mappings: {}".format(
        ["{:#x} size {:#x} locked {:#x}".format(a, b - a, l) for a, b, l in mappings if b - a >= (64 << 20)]))
    return None

def _physical_page(pagemap, vaddr):
    # Returns the physical page holding a virtual address of the memtester process, or None
    try:
        pagemap.seek((vaddr // PAGE_SIZE) * 8)
        entry = struct.unpack("<Q", pagemap.read(8))[0]
        if not entry & (1 << 63):
            return None
        pfn = entry & ((1 << 55) - 1)
        return pfn * PAGE_SIZE if pfn else None
    except Exception:
        return None

def _set_sysctl(path, value):
    old = _read(path)
    try:
        with open(path, "w") as f:
            f.write(value)
    except Exception:
        pass
    return old

def _memtester_size_mb():
    available_kb = 0
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemAvailable:"):
                    available_kb = int(line.split()[1])
    except Exception:
        pass
    return max(64, available_kb // 1024 - MANUAL_RESERVE_MB)

class _PassTracker:
    # Follows memtester's progress output (test names and "setting/testing N" counters) to work out how
    # much of the test is done. Each test sweeps the whole buffer a known number of times.
    def __init__(self, passes):
        self.passes = passes
        self.loop = 0           # Pass memtester is on (1-based), 0 before it starts
        self.done = False
        self.test = ""
        self.test_index = -1
        self.iteration = 0.0    # Fraction of the current test done
        self.carry = ""

    def feed(self, text):
        text = self.carry + text
        last_end = 0
        for m in MEMTESTER_TOKEN_RE.finditer(text):
            if (m.group("step") or m.group("loop")) and m.end() > len(text) - 4:
                # May be cut off (a counter's last digits are in the next read): read it next time
                self.carry = text[m.start():]
                return
            last_end = m.end()
            if m.group("loop"):
                self.loop = int(m.group("loop"))
                self.test, self.test_index, self.iteration = "", -1, 0.0
            elif m.group("test"):
                self.test = m.group("test")
                self.test_index = MEMTESTER_TEST_NAMES.index(self.test)
                self.iteration = 0.0
            elif m.group("step") and self.test_index >= 0:
                iterations = MEMTESTER_TESTS[self.test_index][2]
                self.iteration = min(1.0, (int(m.group("n")) + (0.5 if m.group("step") == "testing" else 0.0)) / iterations)
            elif m.group("done"):
                self.done = True
        self.carry = text[max(last_end, len(text) - 64):]

    def sweeps_done(self):
        # Buffer sweeps finished so far, over all passes
        if self.done:
            return self.passes * MEMTESTER_PASS_SWEEPS
        if self.loop == 0:
            return 0.0
        in_pass = sum(t[1] for t in MEMTESTER_TESTS[:max(0, self.test_index)])
        if self.test_index >= 0:
            in_pass += MEMTESTER_TESTS[self.test_index][1] * self.iteration
        return (self.loop - 1) * MEMTESTER_PASS_SWEEPS + in_pass

    def passes_done(self):
        return self.passes if self.done else max(0, self.loop - 1)

def run_manual_memtest():
    # At startup, before any service starts: runs a manual test if one was asked for.
    # Returns True if it found new bad pages, which then need a reboot to be kept out of use.
    passes = get_manual_memtest_scheduled_passes()
    if not passes:
        return False
    # One test only, even if this one hangs or the power goes out
    cancel_manual_memtest()
    os.sync()
    delete_file(MANUAL_STOP_FILE)
    if not is_memtester_installed():
        _log("Memory test: memtester is not installed")
        return False

    # Free the file cache, so memtester can lock the memory it was using
    os.sync()
    _set_sysctl("/proc/sys/vm/drop_caches", "3")
    size_mb = _memtester_size_mb()
    tested_gb = size_mb / 1024.0
    total_sweeps = passes * MEMTESTER_PASS_SWEEPS
    prior_rate = _seconds_per_gb_sweep()
    start = time.time()
    deadline = start + MANUAL_MAX_HOURS * 3600
    progress = {"passes": passes, "pass": 1, "test": "", "percent": 0, "start": int(start),
                "remaining_seconds": int(total_sweeps * tested_gb * prior_rate), "tested_mb": size_mb,
                "failures": 0, "bad_pages": [], "running": True}
    _write_progress(progress)
    _set_mynode_status(MEMORY_TEST_STATUS)
    # Keep the locked buffer's pages where they are, so their physical addresses stay valid
    old_compact = _set_sysctl("/proc/sys/vm/compact_unevictable_allowed", "0")
    _log("Memory test: testing {} MB, {} pass(es)".format(size_mb, passes))

    tracker = _PassTracker(passes)
    exact_pages = set()     # From the stuck address test, which reports one place
    page_pairs = set()      # From the other tests, which compare two halves and can't say which failed
    failures = 0
    failure_lines = []
    unmapped = 0
    stopped = False
    wantbytes = None
    layout = None
    pagemap = None
    output = b""
    proc = subprocess.Popen([MEMTESTER, "{}M".format(size_mb), str(passes)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        while True:
            if time.time() >= deadline:
                _log("Memory test: stopped after {} hours".format(MANUAL_MAX_HOURS))
                break
            if os.path.isfile(MANUAL_STOP_FILE):
                stopped = True
                break
            ready, _, _ = select.select([proc.stdout], [], [], 1.0)
            if ready:
                chunk = os.read(proc.stdout.fileno(), 65536)
                if not chunk:
                    break   # memtester is done
                tracker.feed(to_string(chunk))
                output += chunk
            # Failure lines and setup lines end in newlines (progress counters use backspaces)
            while b"\n" in output:
                line, output = output.split(b"\n", 1)
                line = to_string(line)
                m = MEMTESTER_GOT_RE.search(line)
                if m:
                    wantbytes = int(m.group(1))
                if "locked." in line and wantbytes:
                    layout = _find_memtester_buffer(proc.pid, wantbytes)
                    pagemap = open("/proc/{}/pagemap".format(proc.pid), "rb")
                stuck = MEMTESTER_STUCK_RE.search(line)
                compare = MEMTESTER_COMPARE_RE.search(line)
                if not (stuck or compare):
                    continue
                failures += 1
                if len(failure_lines) < MANUAL_KEPT_FAILURE_LINES:
                    failure_lines.append("{}: {}".format(tracker.test or "?", line[line.index("FAILURE"):].strip()))
                    _log("Memory test: " + failure_lines[-1])
                if failures > MANUAL_MAX_FAILURES or not layout or not pagemap:
                    unmapped += 1
                    continue
                aligned, bufb = layout
                if stuck:
                    page = _physical_page(pagemap, aligned + int(stuck.group(1), 16))
                    if page is None:
                        unmapped += 1
                    else:
                        exact_pages.add(page)
                else:
                    offset = int(compare.group(1), 16)
                    a = _physical_page(pagemap, aligned + offset)
                    b = _physical_page(pagemap, bufb + offset)
                    if a is None or b is None:
                        unmapped += 1
                    else:
                        page_pairs.add((a, b))
            # Time left: from this run's own speed once it has done enough to measure, before that
            # from earlier runs. A failing test ends early, so with errors this is on the long side.
            sweeps = tracker.sweeps_done()
            elapsed = time.time() - start
            rate = prior_rate
            if sweeps >= MEMTESTER_MEASURE_SWEEPS:
                rate = elapsed / (sweeps * tested_gb)
            progress.update({"pass": max(1, tracker.loop), "test": tracker.test,
                             "percent": int(100 * sweeps / total_sweeps),
                             "remaining_seconds": int((total_sweeps - sweeps) * tested_gb * rate),
                             "failures": failures,
                             "bad_pages": ["0x{:x}".format(p) for p in sorted(exact_pages)]})
            _write_progress(progress)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=30)
            except Exception:
                proc.kill()
        if pagemap:
            pagemap.close()
        _set_sysctl("/proc/sys/vm/compact_unevictable_allowed", old_compact or "1")
        delete_file(MANUAL_STOP_FILE)

    # A compare failure is in one of its two pages. If one of them is already known to be bad, that's
    # it; otherwise both are kept out of use.
    pages = set(exact_pages)
    for a, b in page_pairs:
        if a not in exact_pages and b not in exact_pages:
            pages.update([a, b])
    pages = sorted(pages)
    elapsed = int(time.time() - start)
    sweeps = tracker.sweeps_done()
    run = {"type": "manual", "passes": passes, "passes_done": tracker.passes_done(),
           "percent": int(100 * sweeps / total_sweeps), "seconds": elapsed, "stopped": stopped,
           "tested_mb": size_mb, "failures": failures, "unmapped": unmapped,
           "pages": ["0x{:x}".format(p) for p in pages], "failure_lines": failure_lines}
    if not tracker.done and not stopped:
        run["error"] = "memtester ended early ({})".format(proc.returncode)
    # Learn this device's speed for later estimates, from runs without errors (a failing test ends early)
    rate = None
    if failures == 0 and sweeps >= MEMTESTER_MEASURE_SWEEPS:
        rate = round(elapsed / (sweeps * tested_gb), 4)
    new_pages = _add_run(run, pages, rate)
    _log("Memory test: {} failures, bad pages {}, {} new".format(failures, run["pages"], new_pages))

    progress.update({"running": False, "percent": 100, "remaining_seconds": 0, "failures": failures,
                     "bad_pages": run["pages"], "new_pages": new_pages})
    _write_progress(progress)
    if new_pages:
        state = load_memtest_state()
        write_badram_grub_file([int(p, 16) for p in state["bad_pages"]])
        run_update_grub()
        return True
    _set_mynode_status(None)
    return False


#==================================
# Status
#==================================
def get_memtest_status():
    supported = is_memtest_supported()
    status = {"supported": supported}
    if not supported:
        return status
    state = load_memtest_state()
    runs = state["runs"]
    last_boot = next((r for r in reversed(runs) if r.get("type", "boot") == "boot"), None)
    last_manual = next((r for r in reversed(runs) if r.get("type") == "manual"), None)
    fmt = lambda r: time.strftime("%Y-%m-%d %H:%M", time.localtime(r["time"])) if r else None
    status.update({
        "boot_enabled": is_boot_memtest_enabled(),
        "boot_estimate_minutes": get_boot_memtest_estimate_minutes(),
        "memtester_installed": is_memtester_installed(),
        "pass_options": [{"passes": p, "label": "{} pass{}".format(p, "" if p == 1 else "es")} for p in MANUAL_PASSES],
        "manual_scheduled_passes": get_manual_memtest_scheduled_passes(),
        "bad_pages": state["bad_pages"],
        "bad_page_count": len(state["bad_pages"]),
        "too_many": len(state["bad_pages"]) > MEMTEST_MAX_BAD_PAGES,
        "run_count": state["total_runs"],
        "last_boot": last_boot,
        "last_boot_time": fmt(last_boot),
        "last_manual": last_manual,
        "last_manual_time": fmt(last_manual),
        "last_manual_duration": format_duration(last_manual.get("seconds", 0)) if last_manual else None,
    })
    return status
