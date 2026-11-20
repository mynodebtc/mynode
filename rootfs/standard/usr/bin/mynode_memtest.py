#!/usr/bin/mynode-python

# Memory test helper (amd64). See pynode/memtest_info.py.
#   collect      - at startup, before the drive mounts: save this boot's kernel test result
#   manual       - at startup, before any service starts: run the manual test if one was asked for.
#                  Exits 3 if it found new bad pages (reboot to keep them out of use).
#   apply        - at startup, after the drive mounts: keep the boot options up to date
#   schedule <passes> - run the manual test on the next boot
#   boot on|off  - test memory at every boot
#   clear        - forget the bad pages (after replacing the RAM)
#   status       - print what is known

import json
import sys
from memtest_info import *

USAGE = "Usage: mynode_memtest.py collect|manual|apply|schedule <passes>|boot on|off|clear|status"

def main():
    args = sys.argv[1:]
    if not args or args[0] not in ["collect", "manual", "apply", "schedule", "boot", "clear", "status"]:
        print(USAGE)
        return 2
    action = args[0]
    if action == "status":
        print(json.dumps(get_memtest_status(), indent=2))
        return 0
    if not is_memtest_supported():
        print("Memory test not supported on this device")
        return 0
    if action == "collect":
        if collect_memtest_results():
            run_update_grub()
    elif action == "manual":
        if run_manual_memtest():
            return 3
    elif action == "apply":
        if apply_bad_ram_pages():
            run_update_grub()
    elif action == "schedule":
        if len(args) != 2 or not args[1].isdigit() or not schedule_manual_memtest(int(args[1])):
            print("Passes must be one of {}".format(MANUAL_PASSES))
            return 2
    elif action == "boot":
        if len(args) != 2 or args[1] not in ["on", "off"]:
            print(USAGE)
            return 2
        return 0 if set_boot_memtest_enabled(args[1] == "on") else 1
    elif action == "clear":
        clear_bad_ram_pages()
    return 0

if __name__ == "__main__":
    sys.exit(main())
