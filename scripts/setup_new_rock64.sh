#!/bin/bash

LOCAL_IP=$(python ./scripts/get_local_ip.py)

echo ""
echo "Finished updating rootfs and other files!"
echo ""

clear
echo "Step 1: "
echo "  Flash SD Card with Rock64 Image: out/base_images/rock64_base.img.gz"
echo "  OR"
echo "  If you would rather create your own base image, follow the"
echo "  manual instructions in setup/setup_image_rock64.txt"
echo ""
echo "Press a key when complete..."
read -n 1

clear
echo "Step 2: "
echo "  Insert SD Card into your Rock64 and boot the device"
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
echo "  Login to device with username 'admin' and password 'bolt'"
echo "  Run the following commands. Use bolt at password prompts."
echo "    sudo mynode-local-upgrade ${LOCAL_IP}"
echo "Press a key when complete..."
read -n 1

clear
echo "Step 5:"
echo "  Reboot your device."
echo ""
echo "Press a key when complete..."
read -n 1

echo ""
echo "Congratulations! Your device is now ready!"