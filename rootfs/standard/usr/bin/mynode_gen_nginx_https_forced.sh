#!/bin/bash

# Writes whether Force HTTPS is on for nginx (see /etc/nginx/conf.d/mynode_force_https_apps.conf).
# While it is on, the public apps' plain HTTP ports move the client to their HTTPS port. Run by
# nginx at start and by Settings when the setting changes, followed by an nginx reload.

OUT_FILE="/etc/nginx/mynode/mynode_https_forced.conf"
SETTINGS_FILES=("/mnt/hdd/mynode/settings/https_forced" "/home/bitcoin/.mynode/https_forced")

forced="no"
for f in "${SETTINGS_FILES[@]}"; do
    if [ -f "$f" ]; then
        forced="yes"
    fi
done

mkdir -p "$(dirname "$OUT_FILE")"
TMP_FILE="$(mktemp "${OUT_FILE}.XXXXXX")" || exit 1
if [ "$forced" = "yes" ]; then
    # A rule inside the map in mynode_force_https_apps.conf, matching every host name
    echo "~. 1;" > "$TMP_FILE"
else
    echo "# Force HTTPS is off" > "$TMP_FILE"
fi
chmod 644 "$TMP_FILE"
# The temporary name does not match the include pattern, so nginx never reads a partial file
mv -f "$TMP_FILE" "$OUT_FILE"
