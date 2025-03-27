#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo \"==================== INSTALLING APP ====================\"

# export bitcoin password
BTCPSW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)

# GIT VERIFY IS FAILING DUE TO EXPIRED KEY
# USE GITHUB TARBALL FOR INSTALL FOR NOW

# git clone datum repo
#git clone https://github.com/OCEAN-xyz/datum_gateway.git .

# verify datum
#curl -L "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x1a3e761f19d2cc7785c5502ea291a2c45d0c504a" | gpg --import
#git verify-tag ${VERSION}beta

# checkout the tag
#git checkout ${VERSION}beta

# build datum
cmake . && make

# install datum
touch datum_config.json
echo "{
  \"bitcoind\": {
    \"rpcuser\": \"mynode\",
    \"rpcpassword\": \"auto-config\",
    \"rpcurl\": \"127.0.0.1:8332\"
  },
  \"api\": {
    \"listen_port\": 21000,
    \"modify_conf\": true,
    \"admin_password\": \"bolt\"
  },
  \"mining\": {
    \"pool_address\": \"enter_your_bitcoin_address\",
    \"coinbase_tag_primary\": \"DATUM on mynode\",
    \"coinbase_tag_secondary\": \"DATUM on mynode\"
  },
  \"stratum\": {
    \"listen_port\": 23334
  },
  \"logger\": {
    \"log_level_console\": 2
  },
  \"datum\": {
    \"pool_pass_workers\": true,
    \"pool_pass_full_users\": true,
    \"pooled_mining_only\": true
  }
}
" > datum_config.json

jq --arg BTCPSW "$BTCPSW" '.bitcoind.rpcpassword = $BTCPSW' datum_config.json > datum_config.json.tmp && mv datum_config.json.tmp datum_config.json

cp datum_config.json /mnt/hdd/mynode/datum

echo \"================== DONE INSTALLING APP =================\"