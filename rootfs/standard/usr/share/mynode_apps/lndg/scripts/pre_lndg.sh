#!/bin/bash

source /usr/share/mynode/mynode_functions.sh

set -e

# Set the admin password the first time LNDg starts after an install or reinstall.
# After that the user may change it inside LNDg.
if ! has_app_password lndg; then
    LNDG_ADMIN_PASSWORD=$(generate_app_password)
    export LNDG_ADMIN_PASSWORD
    cd /opt/mynode/lndg
    .venv/bin/python manage.py shell -c "
import os
from django.contrib.auth import get_user_model
admin = get_user_model().objects.get(username='admin')
admin.set_password(os.environ['LNDG_ADMIN_PASSWORD'])
admin.save()
"
    save_app_password lndg "$LNDG_ADMIN_PASSWORD"
fi
