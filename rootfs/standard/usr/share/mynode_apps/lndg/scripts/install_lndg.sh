#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo "==================== INSTALLING APP ===================="

# Setup data folder symlink
mkdir -p /mnt/hdd/mynode/lndg/data
ln -s /mnt/hdd/mynode/lndg/data /opt/mynode/lndg/data

# Install deps (64-bit only, on the Python for apps)
mynode-uv venv --python $APP_PYTHON_MINOR_VERSION .venv
mynode-uv pip install --require-hashes --python .venv/bin/python -r app_data/requirements.lock

# Patch to store file locally
sed -i 's|/usr/local/supervisord.conf|/opt/mynode/lndg/.venv/supervisord.conf|g' initialize.py
#sed -i 's|lndg-admin|admin|g' initialize.py

# Init LNDg (the admin password is set by pre_lndg.sh, so drop the one LNDg generates)
.venv/bin/python initialize.py --lnddir=/mnt/hdd/mynode/lnd --adminuser=admin -wn -dx -sd --sduser=lndg
rm -f data/lndg-admin.txt

# Patch supervisord config
mkdir -p logs
sed -i 's|/var/log|/opt/mynode/lndg/logs|g' .venv/supervisord.conf
sed -i 's|/var/supervisord.pid|/tmp/supervisord.pid|g' .venv/supervisord.conf
sed -i 's|"python|".venv/bin/python|g' .venv/supervisord.conf

# Patch Python - Set GUI to use new log location
sed -i 's|/var/log|/opt/mynode/lndg/logs|g' gui/views.py

# Patch Python - Update Django Settings
echo "" >> lndg/settings.py
echo "SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')" >> lndg/settings.py

# Load initial data
#.venv/bin/python jobs.py

echo "==================== DONE INSTALLING APP ===================="