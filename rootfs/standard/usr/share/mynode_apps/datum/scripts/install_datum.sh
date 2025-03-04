#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

echo \"==================== INSTALLING APP ====================\"

# export bitcoin password
BTCPSW=$(cat /mnt/hdd/mynode/settings/.btcrpcpw)

# git clone datum repo
git clone https://github.com/OCEAN-xyz/datum_gateway.git .

# verify datum
curl -L "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x1a3e761f19d2cc7785c5502ea291a2c45d0c504a" | gpg --import
git verify-tag v0.2.2beta

# build datum
cmake . && make

# install datum
touch /opt/mynode/datum/datum_config.json
echo "{
  \"bitcoind\": {
    \"rpcuser\": \"mynode\",
    \"rpcpassword\": \"auto-config\",
    \"rpcurl\": \"127.0.0.1:8332\",
    \"work_update_seconds\": 40
  },
  \"api\": {
    \"listen_port\": 21000
  },
  \"mining\": {
    \"pool_address\": \"enter your bitcoin address if you solo mine\",
    \"coinbase_tag_primary\": \"DATUM on mynode\",
    \"coinbase_tag_secondary\": \"DATUM on mynode\",
    \"coinbase_unique_id\": 120
  },
  \"stratum\": {
    \"listen_port\": 23334,
    \"max_clients_per_thread\": 1000,
    \"max_threads\": 8,
    \"max_clients\": 2048,
    \"vardiff_min\": 16384,
    \"vardiff_target_shares_min\": 8,
    \"vardiff_quickdiff_count\": 8,
    \"vardiff_quickdiff_delta\": 8,
    \"share_stale_seconds\": 120,
    \"fingerprint_miners\": true
  },
  \"logger\": {
    \"log_level_console\": 2
  },
  \"datum\": {
    \"pool_host\": \"datum-beta1.mine.ocean.xyz\",
    \"pool_port\": 28915,
    \"pool_pubkey\": \"f21f2f0ef0aa1970468f22bad9bb7f4535146f8e4a8f646bebc93da3d89b1406f40d032f09a417d94dc068055df654937922d2c89522e3e8f6f0e649de473003\",
    \"pool_pass_workers\": true,
    \"pool_pass_full_users\": true,
    \"always_pay_self\": true,
    \"pooled_mining_only\": true
  }
}
" >> /opt/mynode/datum/datum_config.json

jq --arg BTCPSW "$BTCPSW" '.bitcoind.rpcpassword = $BTCPSW' /opt/mynode/datum/datum_config.json > /opt/mynode/datum/datum_config.json.tmp && mv /opt/mynode/datum/datum_config.json.tmp /opt/mynode/datum/datum_config.json


echo \"================== DONE INSTALLING APP =================\"