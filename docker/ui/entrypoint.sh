#!/bin/bash
set -e

# Create writable fake runtime directories
mkdir -p /mnt/hdd/mynode/settings
mkdir -p /mnt/hdd/mynode/bitcoin
mkdir -p /mnt/hdd/mynode/lnd
mkdir -p /home/bitcoin/.mynode
mkdir -p /home/admin/.mynode
mkdir -p /var/log/mynode
mkdir -p /tmp/flask_uploads

# Initialize dynamic apps inside the container
/bin/bash /docker/ui/init_dynamic_apps_ui.sh

# Run the UI app
echo "Starting MyNode Flask Web UI in mock mode..."
echo "stable" > /tmp/.mynode_status
exec python /var/www/mynode/mynode.py
