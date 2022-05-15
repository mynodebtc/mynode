#!/bin/bash
set -x
set -e

echo "==================== INSTALLING APP ===================="

# Install deps
virtualenv -p python3 .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/pip install whitenoise
.venv/bin/pip install supervisor

# Patch to store file locally
sed -i 's|/usr/local/etc/supervisord.conf|/opt/mynode/lndg/.venv/supervisord.conf|g' initialize.py
sed -i 's|lndg-admin|admin|g' initialize.py

# Init LNDg
.venv/bin/python initialize.py --lnddir=/mnt/hdd/mynode/lnd --adminpw=bolt -wn -dx -sd --sduser=lndg

# Patch supervisord config
mkdir -p logs
sed -i 's|/var/log|/opt/mynode/lndg/logs|g' .venv/supervisord.conf
sed -i 's|/var/supervisord.pid|/tmp/supervisord.pid|g' .venv/supervisord.conf
sed -i 's|"python|".venv/bin/python|g' .venv/supervisord.conf

# Load initial data
.venv/bin/python jobs.py

echo "==================== DONE INSTALLING APP ===================="