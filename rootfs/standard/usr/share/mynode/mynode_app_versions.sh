#!/bin/bash

BTC_VERSION="22.0"
BTC_VERSION_FILE=/home/bitcoin/.mynode/bitcoin_version
BTC_LATEST_VERSION_FILE=/home/bitcoin/.mynode/bitcoin_version_latest

LND_VERSION="v0.14.2-beta"
LND_VERSION_FILE=/home/bitcoin/.mynode/lnd_version
LND_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lnd_version_latest
LND_UPGRADE_MANIFEST_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-$LND_VERSION.txt
LND_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-guggero-$LND_VERSION.sig

LOOP_VERSION="v0.17.0-beta"
LOOP_VERSION_FILE=/home/bitcoin/.mynode/loop_version
LOOP_LATEST_VERSION_FILE=/home/bitcoin/.mynode/loop_version_latest
LOOP_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/manifest-$LOOP_VERSION.txt
LOOP_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/manifest-$LOOP_VERSION.txt.sig

POOL_VERSION="v0.5.5-alpha"
POOL_VERSION_FILE=/home/bitcoin/.mynode/pool_version
POOL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/pool_version_latest
POOL_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/pool/releases/download/$POOL_VERSION/manifest-$POOL_VERSION.txt
POOL_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/pool/releases/download/$POOL_VERSION/manifest-$POOL_VERSION.sig

LIT_VERSION="v0.6.5-alpha"
LIT_VERSION_FILE=/home/bitcoin/.mynode/lit_version
LIT_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lit_version_latest
LIT_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/lightning-terminal/releases/download/$LIT_VERSION/manifest-$LIT_VERSION.txt
LIT_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/lightning-terminal/releases/download/$LIT_VERSION/manifest-$LIT_VERSION.sig

ELECTRS_VERSION="v0.9.3"
ELECTRS_VERSION_FILE=/home/bitcoin/.mynode/electrs_version
ELECTRS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/electrs_version_latest

MEMPOOL_VERSION="v2.3.1"
MEMPOOL_VERSION_FILE=/mnt/hdd/mynode/settings/mempool_version
MEMPOOL_LATEST_VERSION_FILE=/mnt/hdd/mynode/settings/mempool_version_latest

LNDHUB_VERSION="v1.4.1"
LNDHUB_VERSION_FILE=/home/bitcoin/.mynode/lndhub_version
LNDHUB_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lndhub_version_latest

CARAVAN_VERSION="v0.3.13"
CARAVAN_SETTINGS_UPDATE_FILE=/home/bitcoin/.mynode/caravan_settings_1
CARAVAN_VERSION_FILE=/home/bitcoin/.mynode/caravan_version
CARAVAN_LATEST_VERSION_FILE=/home/bitcoin/.mynode/caravan_version_latest

CORSPROXY_VERSION="v1.7.0"
CORSPROXY_VERSION_FILE=/home/bitcoin/.mynode/corsproxy_version
CORSPROXY_LATEST_VERSION_FILE=/home/bitcoin/.mynode/corsproxy_version_latest

JOINMARKET_VERSION="v0.8.2"
JOINMARKET_VERSION_FILE=/home/bitcoin/.mynode/joinmarket_version
JOINMARKET_LATEST_VERSION_FILE=/home/bitcoin/.mynode/joinmarket_version_latest

JOININBOX_VERSION="v0.6.7"
JOININBOX_VERSION_FILE=/home/bitcoin/.mynode/joininbox_version
JOININBOX_LATEST_VERSION_FILE=/home/bitcoin/.mynode/joininbox_version_latest

SECP256K1_VERSION=486205aa68b7f1d4291f78fa20bc4485fd843e1c
SECP256K1_VERSION_FILE=/home/bitcoin/.mynode/secp256k1_version
SECP256K1_LATEST_VERSION_FILE=/home/bitcoin/.mynode/secp256k1_version_latest

WHIRLPOOL_VERSION="0.10.13"
WHIRLPOOL_UPLOAD_FILE_ID="c1bb32bac6d4b377f625c996387375c2"
# Update sig file at /usr/share/whirlpool/whirlpool.asc for each release
WHIRLPOOL_VERSION_FILE=/home/bitcoin/.mynode/whirlpool_version
WHIRLPOOL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/whirlpool_version_latest

DOJO_VERSION="v1.14.0"
# Find at https://code.samourai.io/dojo/samourai-dojo/-/releases in fingerprints
DOJO_TAR_HASH="17aa26481e0a569719875687ed1744e3e45f3a7a70306298345d0a59acd17ad3"
DOJO_VERSION_FILE=/mnt/hdd/mynode/settings/dojo_version
DOJO_LATEST_VERSION_FILE=/mnt/hdd/mynode/settings/dojo_version_latest

RTL_VERSION="v0.12.2"
RTL_VERSION_FILE=/home/bitcoin/.mynode/rtl_version
RTL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/rtl_version_latest

BTCPAYSERVER_VERSION="1.4.7"
BTCPAYSERVER_NBXPLORER_VERSION="2.2.20"
BTCPAYSERVER_POSTGRES_VERSION="13.6"
BTCPAYSERVER_VERSION_FILE=/home/bitcoin/.mynode/btcpayserver_version
BTCPAYSERVER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/btcpayserver_version_latest

BTCRPCEXPLORER_VERSION="v3.3.0"
BTCRPCEXPLORER_VERSION_FILE=/home/bitcoin/.mynode/btcrpcexplorer_version
BTCRPCEXPLORER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/btcrpcexplorer_version_latest

LNBITS_VERSION=bcecf6d43111199302d9f7152ecb7e7a4735662a         # Github hash to download
LNBITS_VERSION_FILE=/home/bitcoin/.mynode/lnbits_version
LNBITS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lnbits_version_latest

SPECTER_VERSION="1.8.1"
SPECTER_VERSION_FILE=/home/bitcoin/.mynode/specter_version
SPECTER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/specter_version_latest

THUNDERHUB_VERSION="v0.13.7"
THUNDERHUB_VERSION_FILE=/home/bitcoin/.mynode/thunderhub_version
THUNDERHUB_LATEST_VERSION_FILE=/home/bitcoin/.mynode/thunderhub_version_latest

LNDMANAGE_VERSION="0.14.0"
LNDMANAGE_VERSION_FILE=/home/bitcoin/.mynode/lndmanage_version
LNDMANAGE_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lndmanage_version_latest

LNDCONNECT_VERSION="v0.2.0"
LNDCONNECT_VERSION_FILE=/home/bitcoin/.mynode/lndconnect_version
LNDCONNECT_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lndconnect_version_latest

CKBUNKER_VERSION="v0.9"
CKBUNKER_VERSION_FILE=/home/bitcoin/.mynode/ckbunker_version
CKBUNKER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/ckbunker_version_latest

BOS_VERSION="11.57.0"
BOS_VERSION_FILE=/home/bitcoin/.mynode/bos_version
BOS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/bos_version_latest

SPHINXRELAY_VERSION="v2.2.5"
SPHINXRELAY_VERSION_FILE=/home/bitcoin/.mynode/sphinxrelay_version
SPHINXRELAY_LATEST_VERSION_FILE=/home/bitcoin/.mynode/sphinxrelay_version_latest

PYBLOCK_VERSION="v1.1.9"
PYBLOCK_VERSION_FILE=/home/bitcoin/.mynode/pyblock_version
PYBLOCK_LATEST_VERSION_FILE=/home/bitcoin/.mynode/pyblock_version_latest

WARDEN_VERSION="0.91"
WARDEN_VERSION_FILE=/home/bitcoin/.mynode/warden_version
WARDEN_LATEST_VERSION_FILE=/home/bitcoin/.mynode/warden_version_latest

WARDEN_TERMINAL_VERSION=c327e84fb95fa6e29bb24d641e6215b3942d8da4
WARDEN_TERMINAL_VERSION_FILE=/home/bitcoin/.mynode/wardenterminal_version
WARDEN_TERMINAL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/wardenterminal_version_latest

NETDATA_VERSION="v1.32.1"
NETDATA_VERSION_FILE=/mnt/hdd/mynode/settings/netdata_version
NETDATA_LATEST_VERSION_FILE=/mnt/hdd/mynode/settings/netdata_version_latest

WEBSSH2_VERSION="v0.2.10-0"
WEBSSH2_VERSION_FILE=/mnt/hdd/mynode/settings/webssh2_version
WEBSSH2_LATEST_VERSION_FILE=/mnt/hdd/mynode/settings/webssh2_version_latest

# Dependency versions
PYTHON_VERSION="3.8.9"

PYTHON_ARM32_GRPCIO_VERSION="1.40.0"

NODE_JS_VERSION="14.x"
NODE_NPM_VERSION="^8.1.0"

RUST_VERSION="1.56.1"

# Check for override files
if [ -f /usr/share/mynode/mynode_app_versions_custom.sh ]; then
    source /usr/share/mynode/mynode_app_versions_custom.sh
elif [ -f /mnt/hdd/mynode/settings/mynode_app_versions_custom.sh ]; then
    source /mnt/hdd/mynode/settings/mynode_app_versions_custom.sh
fi
