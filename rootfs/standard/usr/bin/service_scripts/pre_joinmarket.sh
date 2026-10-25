#!/bin/bash

# Remove wallet lock files left behind when JoinMarket did not exit cleanly.
# JoinMarket will not open a wallet while its lock file exists, and does not
# check whether the process that wrote the lock is still running.

WALLET_DIR=/mnt/hdd/mynode/joinmarket/wallets
BOOT_TIME=$(awk '/^btime/ {print $2}' /proc/stat)

for LOCK in "$WALLET_DIR"/.*.jmdat.lock; do
    [ -f "$LOCK" ] || continue

    # Written before this boot, so no running process can hold it
    if [ -n "$BOOT_TIME" ] && [ "$(stat -c %Y "$LOCK")" -lt "$BOOT_TIME" ]; then
        echo "Removing lock file from before boot: $LOCK"
        rm -f "$LOCK"
        continue
    fi

    # Keep it if the PID inside is a running JoinMarket script (e.g. a yield generator from JoininBox)
    PID=$(head -c 32 "$LOCK")
    if [[ "$PID" =~ ^[0-9]+$ ]] && [ "$(stat -c %U /proc/$PID 2>/dev/null)" = "joinmarket" ]; then
        PROC=$(tr '\0' ' ' < /proc/$PID/cmdline 2>/dev/null)
        if [[ "$PROC" =~ \.py ]]; then
            echo "Keeping lock file held by PID $PID ($PROC): $LOCK"
            continue
        fi
    fi

    echo "Removing stale lock file (PID '$PID'): $LOCK"
    rm -f "$LOCK"
done

exit 0
