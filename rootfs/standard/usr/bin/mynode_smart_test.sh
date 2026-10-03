#!/bin/bash

# Runs a SMART short self-test on the MyNode drive and saves a report.
# While running, /tmp/smart_test_running holds the expected finish time (epoch seconds).
# Short tests usually take 1-2 minutes.

RUNNING_FILE=/tmp/smart_test_running
RESULTS_FILE=/tmp/smart_test_results
TMP_RESULTS=/tmp/smart_test_results.tmp

exec 9>/tmp/smart_test.lock
flock -n 9 || exit 1

echo "" > $RUNNING_FILE
trap "rm -f $RUNNING_FILE" EXIT
rm -f $TMP_RESULTS

finish() {
    mv -f $TMP_RESULTS $RESULTS_FILE
    exit 0
}

PARTITION=$(cat /tmp/.mynode_drive 2>/dev/null)
DRIVE=""
if [ -n "$PARTITION" ]; then
    DRIVE="/dev/$(lsblk -no pkname $PARTITION 2>/dev/null)"
fi
if [ -z "$PARTITION" ] || [ ! -b "$DRIVE" ] || [ "$DRIVE" = "/dev/" ]; then
    echo "MyNode drive not found." > $TMP_RESULTS
    finish
fi
if ! command -v smartctl > /dev/null; then
    echo "smartmontools is not installed. It will be installed by the next MyNode upgrade." > $TMP_RESULTS
    finish
fi

# USB adapters smartctl does not recognize usually support SAT
DEV_ARGS=""
smartctl -i $DRIVE > /dev/null 2>&1
if [ $(( $? & 3 )) -ne 0 ]; then
    DEV_ARGS="-d sat"
fi

# smartctl runs NVMe self-tests only from version 7.4 (Debian 12 has 7.3), so use nvme-cli for those
NVME=""
if [[ "$DRIVE" == /dev/nvme* ]]; then
    NVME=$(command -v nvme)
fi

# "progress" prints the percent of the running NVMe self-test that remains, or nothing when none is
# running. "result" prints the latest self-test log entry in the format smartctl uses for NVMe.
nvme_self_test_log() {
    $NVME self-test-log -o json $DRIVE 2>/dev/null | python3 -c '
import json, sys
log = json.load(sys.stdin)
if sys.argv[1] == "progress":
    if log["Current Device Self-Test Operation"] != 0:
        print(100 - log["Current Device Self-Test Completion"])
    sys.exit()
tests = {1: "Short", 2: "Extended", 14: "Vendor specific"}
results = {0: "Completed without error", 1: "Aborted: by host", 2: "Aborted: controller reset",
           3: "Aborted: namespace removed", 4: "Aborted: format", 5: "Fatal or unknown error",
           6: "Failed: unknown segment", 7: "Failed: segment", 8: "Aborted: unknown reason",
           9: "Aborted: sanitize"}
latest = log["List of Valid Reports"][0]
if latest["Self test result"] == 15:
    sys.exit()
print("Self-test Log (nvme-cli)")
print("Num  Test_Description  Status                       Power_on_Hours")
print(" 0   %-16s  %-27s  %14s" % (tests.get(latest["Self test code"], "Unknown"),
      results.get(latest["Self test result"], "Unknown result"), latest.get("Power on hours", "-")))
' "$1"
}

# Prints the percent of the self-test that remains (or nothing, if the drive does not say), and
# returns non-zero once no self-test is running
self_test_remaining() {
    if [ -n "$NVME" ]; then
        local REMAINING=$(nvme_self_test_log progress)
        [ -n "$REMAINING" ] && echo $REMAINING
        return
    fi
    local STATUS=$(smartctl $DEV_ARGS -c $DRIVE 2>/dev/null | grep -iE -A1 "self-test.*in progress")
    [ -n "$STATUS" ] || return 1
    # ATA reports "90% of test remaining", NVMe "(10% completed)"
    local REMAINING=$(echo "$STATUS" | grep -oE "[0-9]+% of test remaining" | grep -oE "[0-9]+")
    local COMPLETED=$(echo "$STATUS" | grep -oE "[0-9]+% completed" | grep -oE "[0-9]+")
    if [ -z "$REMAINING" ] && [ -n "$COMPLETED" ]; then
        REMAINING=$(( 100 - COMPLETED ))
    fi
    echo "$REMAINING"
}

abort_self_test() {
    if [ -n "$NVME" ]; then
        $NVME device-self-test $DRIVE -s 0xf > /dev/null 2>&1
    else
        smartctl $DEV_ARGS -X $DRIVE > /dev/null 2>&1
    fi
}

STARTED=0
MINUTES=2
if [ -n "$NVME" ]; then
    # NVMe short tests take at most 2 minutes. The broadcast namespace tests every namespace.
    $NVME device-self-test $DRIVE -n 0xffffffff -s 1 > /dev/null 2>&1 && STARTED=1
else
    START_OUTPUT=$(smartctl $DEV_ARGS -t short $DRIVE 2>&1)
    if echo "$START_OUTPUT" | grep -qi "has begun"; then
        STARTED=1
        MINUTES=$(echo "$START_OUTPUT" | grep -oiE "wait [0-9]+ minute" | grep -oE "[0-9]+")
        MINUTES=${MINUTES:-2}
    fi
fi

if [ $STARTED -eq 1 ]; then
    echo $(( $(date +%s) + MINUTES * 60 )) > $RUNNING_FILE

    # Wait for the drive to finish, giving up at 5x its own estimate (at least 10 minutes)
    WAIT_MINUTES=$(( MINUTES * 5 ))
    if [ $WAIT_MINUTES -lt 10 ]; then
        WAIT_MINUTES=10
    fi
    GIVE_UP_TIME=$(( $(date +%s) + WAIT_MINUTES * 60 ))
    sleep 20
    while REMAINING=$(self_test_remaining); do
        if [ $(date +%s) -ge $GIVE_UP_TIME ]; then
            abort_self_test
            echo "The drive did not finish the short self-test within $WAIT_MINUTES minutes, so it was stopped. Some drives cannot run a self-test while they are busy. Showing the drive's health data instead." >> $TMP_RESULTS
            echo "" >> $TMP_RESULTS
            break
        fi
        echo "$REMAINING" > /tmp/smart_test_remaining
        sleep 10
    done
    rm -f /tmp/smart_test_remaining
else
    echo "The short self-test could not be started on this drive. Showing the drive's health data instead." >> $TMP_RESULTS
    echo "" >> $TMP_RESULTS
fi

echo "Drive: $DRIVE" >> $TMP_RESULTS
smartctl $DEV_ARGS -i -H -A -l selftest $DRIVE 2>&1 | sed '1,3d' >> $TMP_RESULTS
if [ -n "$NVME" ]; then
    nvme_self_test_log result >> $TMP_RESULTS
fi
finish
