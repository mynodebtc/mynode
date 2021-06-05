#!/bin/bash

BTC_VERSION="0.21.1"
BTC_VERSION_FILE=/home/bitcoin/.mynode/bitcoin_version
BTC_LATEST_VERSION_FILE=/home/bitcoin/.mynode/bitcoin_version_latest

LND_VERSION="v0.12.1-beta"
LND_VERSION_FILE=/home/bitcoin/.mynode/lnd_version
LND_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lnd_version_latest
LND_UPGRADE_MANIFEST_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-$LND_VERSION.txt
LND_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-roasbeef-$LND_VERSION.sig

LOOP_VERSION="v0.14.0-beta"
LOOP_VERSION_FILE=/home/bitcoin/.mynode/loop_version
LOOP_LATEST_VERSION_FILE=/home/bitcoin/.mynode/loop_version_latest
LOOP_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/manifest-$LOOP_VERSION.txt
LOOP_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/manifest-$LOOP_VERSION.txt.sig

POOL_VERSION="v0.5.0-alpha" 
POOL_VERSION_FILE=/home/bitcoin/.mynode/pool_version
POOL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/pool_version_latest
POOL_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/pool/releases/download/$POOL_VERSION/manifest-$POOL_VERSION.txt
POOL_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/pool/releases/download/$POOL_VERSION/manifest-$POOL_VERSION.txt.sig

LIT_VERSION="v0.4.1-alpha" 
LIT_VERSION_FILE=/home/bitcoin/.mynode/lit_version
LIT_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lit_version_latest
LIT_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/lightning-terminal/releases/download/$LIT_VERSION/manifest-$LIT_VERSION.txt
LIT_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/lightning-terminal/releases/download/$LIT_VERSION/manifest-guggero-$LIT_VERSION.sig

ELECTRS_VERSION="v0.8.9" 
ELECTRS_VERSION_FILE=/home/bitcoin/.mynode/electrs_version
ELECTRS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/electrs_version_latest

MEMPOOL_VERSION="v2.1.2"
MEMPOOL_VERSION_FILE=/mnt/hdd/mynode/settings/mempool_version
MEMPOOL_LATEST_VERSION_FILE=/mnt/hdd/mynode/settings/mempool_version_latest

LNDHUB_VERSION="v1.3.4"
LNDHUB_VERSION_FILE=/home/bitcoin/.mynode/lndhub_version
LNDHUB_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lndhub_version_latest

CARAVAN_VERSION="v0.3.5"
CARAVAN_SETTINGS_UPDATE_FILE=/home/bitcoin/.mynode/caravan_settings_1
CARAVAN_VERSION_FILE=/home/bitcoin/.mynode/caravan_version
CARAVAN_LATEST_VERSION_FILE=/home/bitcoin/.mynode/caravan_version_latest

CORSPROXY_VERSION="v1.7.0"
CORSPROXY_VERSION_FILE=/home/bitcoin/.mynode/corsproxy_version
CORSPROXY_LATEST_VERSION_FILE=/home/bitcoin/.mynode/corsproxy_version_latest

JOINMARKET_VERSION="v0.8.2"
JOINMARKET_VERSION_FILE=/home/bitcoin/.mynode/joinmarket_version
JOINMARKET_LATEST_VERSION_FILE=/home/bitcoin/.mynode/joinmarket_version_latest

JOININBOX_VERSION="v0.4.0"
JOININBOX_VERSION_FILE=/home/bitcoin/.mynode/joininbox_version
JOININBOX_LATEST_VERSION_FILE=/home/bitcoin/.mynode/joininbox_version_latest

WHIRLPOOL_VERSION="0.10.10"
WHIRLPOOL_UPLOAD_FILE_ID="e4a90d89e67b90b7c715a12264ebc8fd"
WHIRLPOOL_UPLOAD_SIG_ID="c3478374cddfd78869a6b93f5c78d098"
WHIRLPOOL_VERSION_FILE=/home/bitcoin/.mynode/whirlpool_version
WHIRLPOOL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/whirlpool_version_latest

DOJO_VERSION="v1.9.0"
DOJO_TAR_HASH="b9709c18bb58f514a2f1db948b421b691b22fbf7713f5a68ce9627f35fcbf306"
DOJO_VERSION_FILE=/mnt/hdd/mynode/settings/dojo_version
DOJO_LATEST_VERSION_FILE=/mnt/hdd/mynode/settings/dojo_version_latest

RTL_VERSION="v0.10.2"
RTL_VERSION_FILE=/home/bitcoin/.mynode/rtl_version
RTL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/rtl_version_latest

BTCPAYSERVER_VERSION="1.0.7.2"
BTCPAYSERVER_NBXPLORER_VERSION="2.1.49"
BTCPAYSERVER_VERSION_FILE=/home/bitcoin/.mynode/btcpayserver_version
BTCPAYSERVER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/btcpayserver_version_latest

BTCRPCEXPLORER_VERSION="v3.1.1"
BTCRPCEXPLORER_VERSION_FILE=/home/bitcoin/.mynode/btcrpcexplorer_version
BTCRPCEXPLORER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/btcrpcexplorer_version_latest

LNBITS_VERSION=503c981bc970f4ab894f50198dbd6833cae8f6e0         # Github hash to download
LNBITS_VERSION_FILE=/home/bitcoin/.mynode/lnbits_version
LNBITS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lnbits_version_latest

SPECTER_VERSION="1.4.2"
SPECTER_VERSION_FILE=/home/bitcoin/.mynode/specter_version
SPECTER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/specter_version_latest

THUNDERHUB_VERSION="v0.12.17"
THUNDERHUB_VERSION_FILE=/home/bitcoin/.mynode/thunderhub_version
THUNDERHUB_LATEST_VERSION_FILE=/home/bitcoin/.mynode/thunderhub_version_latest

LNDMANAGE_VERSION="0.12.0"
LNDMANAGE_VERSION_FILE=/home/bitcoin/.mynode/lndmanage_version
LNDMANAGE_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lndmanage_version_latest

LNDCONNECT_VERSION="v0.2.0"
LNDCONNECT_VERSION_FILE=/home/bitcoin/.mynode/lndconnect_version
LNDCONNECT_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lndconnect_version_latest

CKBUNKER_VERSION="v0.9"
CKBUNKER_VERSION_FILE=/home/bitcoin/.mynode/ckbunker_version
CKBUNKER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/ckbunker_version_latest

BOS_VERSION="9.2.0"
BOS_VERSION_FILE=/home/bitcoin/.mynode/bos_version
BOS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/bos_version_latest

SPHINXRELAY_VERSION="v2.1.3"
SPHINXRELAY_VERSION_FILE=/home/bitcoin/.mynode/sphinxrelay_version
SPHINXRELAY_LATEST_VERSION_FILE=/home/bitcoin/.mynode/sphinxrelay_version_latest

PYBLOCK_VERSION="v0.9.7.3"
PYBLOCK_VERSION_FILE=/home/bitcoin/.mynode/pyblock_version
PYBLOCK_LATEST_VERSION_FILE=/home/bitcoin/.mynode/pyblock_version_latest

WARDEN_VERSION="0.91"
WARDEN_VERSION_FILE=/home/bitcoin/.mynode/warden_version
WARDEN_LATEST_VERSION_FILE=/home/bitcoin/.mynode/warden_version_latest

WEBSSH2_VERSION="v0.2.10-0"
WEBSSH2_VERSION_FILE=/mnt/hdd/mynode/settings/webssh2_version
WEBSSH2_LATEST_VERSION_FILE=/mnt/hdd/mynode/settings/webssh2_version_latest
