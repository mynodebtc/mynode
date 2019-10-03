#!/bin/bash

# Device info
# Now calculated in main config file...

# Other Info
UPGRADE_DOWNLOAD_URL="http://www.mynodebtc.com/device_api/download_latest_standard.php?type=${DEVICE_TYPE}&product_key=${PRODUCT_KEY}&serial=${SERIAL_NUM}"
UPGRADE_DOWNLOAD_SIGNATURE_URL="http://www.mynodebtc.com/device/hashes/mynode_release_latest_${DEVICE_TYPE}.sha256"