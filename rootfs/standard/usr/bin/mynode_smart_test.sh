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

START_OUTPUT=$(smartctl $DEV_ARGS -t short $DRIVE 2>&1)
if echo "$START_OUTPUT" | grep -qi "has begun"; then
    MINUTES=$(echo "$START_OUTPUT" | grep -oiE "wait [0-9]+ minute" | grep -oE "[0-9]+")
    MINUTES=${MINUTES:-2}
    echo $(( $(date +%s) + MINUTES * 60 )) > $RUNNING_FILE

    # Wait for the drive to finish, giving up at 5x its own estimate (at least 10 minutes)
    WAIT_MINUTES=$(( MINUTES * 5 ))
    if [ $WAIT_MINUTES -lt 10 ]; then
        WAIT_MINUTES=10
    fi
    GIVE_UP_TIME=$(( $(date +%s) + WAIT_MINUTES * 60 ))
    sleep 20
    while true; do
        STATUS=$(smartctl $DEV_ARGS -c $DRIVE 2>/dev/null | grep -iE -A1 "self-test.*in progress")
        if [ -z "$STATUS" ]; then
            break
        fi
        if [ $(date +%s) -ge $GIVE_UP_TIME ]; then
            smartctl $DEV_ARGS -X $DRIVE > /dev/null 2>&1
            echo "The drive did not finish the short self-test within $WAIT_MINUTES minutes, so it was stopped. Some drives cannot run a self-test while they are busy. Showing the drive's health data instead." >> $TMP_RESULTS
            echo "" >> $TMP_RESULTS
            break
        fi
        # ATA reports "90% of test remaining", NVMe "(10% completed)"
        REMAINING=$(echo "$STATUS" | grep -oE "[0-9]+% of test remaining" | grep -oE "[0-9]+")
        COMPLETED=$(echo "$STATUS" | grep -oE "[0-9]+% completed" | grep -oE "[0-9]+")
        if [ -z "$REMAINING" ] && [ -n "$COMPLETED" ]; then
            REMAINING=$(( 100 - COMPLETED ))
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
finish
