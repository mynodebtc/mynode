#!/bin/bash

# This will run prior to launching the application

# WeTTY only accepts browser connections from the origins it is given, so list each address the
# node can be opened at: its IPs, host name, mynode.local, Tailscale name and Tor address. It is
# opened over HTTPS only (through nginx), since its pages do not load over HTTP.
ORIGINS_FILE=/opt/mynode/wetty/.allowed_origins

HOSTS="localhost 127.0.0.1 mynode.local"
NAME=$(hostname | tr '[:upper:]' '[:lower:]')
if [ -n "$NAME" ]; then
    HOSTS="$HOSTS $NAME $NAME.local"
fi
TAILSCALE=""
if command -v tailscale > /dev/null 2>&1; then
    TAILSCALE=$(timeout 5 tailscale status --json 2>/dev/null | python3 -c '
import json, sys
s = json.load(sys.stdin).get("Self", {})
print(" ".join([s.get("DNSName", "").rstrip(".")] + s.get("TailscaleIPs", [])))' 2>/dev/null)
fi
for addr in $(hostname -I) $TAILSCALE; do
    case "$addr" in
        fe80:*) ;;                      # Link-local IPv6 needs a zone ID, which browsers do not send
        *:*) HOSTS="$HOSTS [$addr]" ;;
        *) HOSTS="$HOSTS $addr" ;;
    esac
done

ORIGINS=""
for h in $HOSTS; do
    ORIGINS="$ORIGINS,https://$h:2225"
done

ONION=$(cat /var/lib/tor/mynode_wetty/hostname 2>/dev/null)
if [ -n "$ONION" ]; then
    ORIGINS="$ORIGINS,https://$ONION"
fi

echo "ALLOWEDORIGINS=${ORIGINS#,}" > $ORIGINS_FILE
chmod 644 $ORIGINS_FILE
