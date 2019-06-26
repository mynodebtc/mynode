#!/bin/bash

LOCAL_IP=$(python ./scripts/get_local_ip.py)

echo ""
echo "Finished updating rootfs and other files!"
echo ""

clear
echo "Step 1: "
echo "  Flash SD Card with Rock64: out/base_images/rock64_base.img.gz"
echo "  OR"
echo "  If you would rather create your own base image, follow the"
echo "  manual instructions in setup/setup_image_rock64.txt"
echo ""
echo "Press a key when complete..."
read -n 1

clear
echo "Step 2: "
echo "  Insert SD Card into Rock64 and boot the device"
echo ""
echo "Press a key when complete..."
read -n 1

clear
echo "Step 3: "
echo "  Login to device with username 'admin' and password 'bolt'"
echo "  Run the following commands. Use bolt at password prompts."
echo "    wget http://${LOCAL_IP}:8000/setup_rock64.sh -O setup_rock64.sh"
echo "    chmod +x setup_rock64.sh"
echo "    sudo ./setup_rock64.sh ${LOCAL_IP}"
echo ""
echo "Press a key when complete..."
read -n 1

clear
echo "Step 4:"
echo "  Login to device with username 'admin' and password 'bolt'"
echo "  Run the following commands. Use bolt at password prompts."
echo "  "
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