#!/bin/bash
RED='\033[0;31m'
NC='\033[0m' # No Color
BLUE='\033[0;34m'

echo ""
echo "-----------------------------------------------------------------"
echo -e "${BLUE}"
echo "      _   _           __        ___    ____     _"
echo "     | |_| |__   ___  \ \      / / \  |  _ \ __| | ___ _ __"
echo "     | __|  _ \ / _ \  \ \ /\ / / _ \ | |_) / _  |/ _ \  _  |"
echo "     | |_| | | |  __/   \ V  V / ___ \|  _ < (_| |  __/ | | |"
echo "      \__|_| |_|\___|    \_/\_/_/   \_\_| \_\__,_|\___|_| |_|"
echo ""
echo -e "${NC}"
echo "-----------------------------------------------------------------"
echo ""
echo " Starting Setup..."
echo " -----------------"
echo " Downloading the WARden source code from GitHub and Unzip.... "
cd /var/www/mynode

# Save current version of apps.html
sudo cp templates/includes/apps.html templates/includes/app_backup.html

# download files
sudo wget https://github.com/pxsocs/warden_mynode/archive/production.zip
sudo unzip production.zip -d /var/www/mynode
sudo cp -r warden_mynode-production/. /var/www/mynode
sudo rm production.zip
sudo rm -r warden_mynode-production

echo " Installing Python Dependencies...."
sudo /usr/bin/python -m pip install python-dateutil pandas simplejson

# if argument install-icon exists, make changes to app.html
if [[ " $@ " =~ " -install-icon " ]]; then
    echo " Icon Installed to MyNode"
    sudo rm templates/includes/app_backup.html
else
    echo " Icon installation skipped. To add icon run: "
    echo -e "${BLUE}"
    echo " $ source ./warden_upgrade.sh -install-icon"
    echo -e "${NC}"
    sudo rm templates/includes/app.html
    sudo cp templates/includes/app_backup.html templates/includes/apps.html
fi

echo " Restarting web server...."
sudo systemctl restart www
echo -e "${BLUE}"
echo " Done. Navigate to mynode.local/warden to open WARden."
echo " -----------------------------------------------------"
echo -e "${NC}"