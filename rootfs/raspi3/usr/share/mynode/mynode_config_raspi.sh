#!/bin/bash

# Device info
IS_RASPI=1
IS_RASPI3=1
IS_RASPI4=0
IS_ROCK64=0
IS_STANDARD=1
DEVICE_TYPE="raspi3"

# Other Info
UPGRADE_DOWNLOAD_URL="http://www.mynodebtc.com/device_api/download_latest_standard.php?type=${DEVICE_TYPE}&product_key=${PRODUCT_KEY}&serial=${SERIAL_NUM}"
UPGRADE_DOWNLOAD_SIGNATURE_URL="http://www.mynodebtc.com/device/hashes/mynode_release_latest_${DEVICE_TYPE}.sha256"