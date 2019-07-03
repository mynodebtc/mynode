#!/bin/bash

# Device info
IS_RASPI=1
IS_ROCK64=0
IS_STANDARD=1
DEVICE_TYPE="raspi4"

# Other Info
UPGRADE_DOWNLOAD_URL="http://www.mynodebtc.com/device_api/download_latest_standard.php?type=${DEVICE_TYPE}&product_key=${PRODUCT_KEY}&serial=${SERIAL_NUM}"
UPGRADE_DOWNLOAD_SIGNATURE_URL="http://www.mynodebtc.com/device/mynode_release_latest_raspi.sha256"