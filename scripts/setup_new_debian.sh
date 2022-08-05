#!/bin/bash

LOCAL_IP=$(python ./scripts/get_local_ip.py)

echo ""
echo "Finished updating rootfs and other files!"
echo ""

clear
echo "Step 1: "
echo "  Install your a Debian Image:"
echo "  Setup image for use with myNode:"
echo "    See manual instructions in doc/setup_base_image_debian.md"
echo ""
echo "Press a key when complete..."
read -n 1

clear
echo "Step 2: "
echo "  Reboot Device"
echo ""
echo "Press a key when complete..."
read -n 1

clear
echo "Step 3: "
echo "  Login to device with username 'admin' and password 'bolt'"
echo "  Run the following commands. Use bolt at password prompts."
echo "    wget http://${LOCAL_IP}:8000/setup_device.sh -O setup_device.sh"
echo "    chmod +x setup_device.sh"
echo "    sudo ./setup_device.sh ${LOCAL_IP}"
echo ""
echo "Press a key when complete..."
read -n 1

clear
echo "Step 4:"
echo "  Reboot your device."
echo ""
echo "Press a key when complete..."
read -n 1

clear
echo "Congratulations! Your device is now ready!"
echo "  Access it via a web browser at http://mynode.local/ or http://<device ip>/"
echo "  Access it via SSH using the default credentials: admin / bolt"
echo "  You should change your password on the settings page in the web GUI"
echo ""
