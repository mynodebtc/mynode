#!/bin/bash

BTC_VERSION="0.21.0"
BTC_VERSION_FILE=/home/bitcoin/.mynode/bitcoin_version
BTC_LATEST_VERSION_FILE=/home/bitcoin/.mynode/bitcoin_version_latest

LND_VERSION="v0.12.1-beta"
LND_VERSION_FILE=/home/bitcoin/.mynode/lnd_version
LND_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lnd_version_latest
LND_UPGRADE_MANIFEST_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-$LND_VERSION.txt
LND_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-roasbeef-$LND_VERSION.sig

LOOP_VERSION="v0.11.4-beta" 
LOOP_VERSION_FILE=/home/bitcoin/.mynode/loop_version
LOOP_LATEST_VERSION_FILE=/home/bitcoin/.mynode/loop_version_latest
LOOP_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/manifest-$LOOP_VERSION.txt
LOOP_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/manifest-$LOOP_VERSION.txt.sig

POOL_VERSION="v0.4.1-alpha" 
POOL_VERSION_FILE=/home/bitcoin/.mynode/pool_version
POOL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/pool_version_latest
POOL_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/pool/releases/download/$POOL_VERSION/manifest-$POOL_VERSION.txt
POOL_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/pool/releases/download/$POOL_VERSION/manifest-$POOL_VERSION.txt.sig

ELECTRS_VERSION="v0.8.6" 
ELECTRS_VERSION_FILE=/home/bitcoin/.mynode/electrs_version
ELECTRS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/electrs_version_latest

LNDHUB_VERSION="v1.3.0"
LNDHUB_VERSION_FILE=/home/bitcoin/.mynode/lndhub_version
LNDHUB_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lndhub_version_latest

CARAVAN_VERSION="v0.3.5"
CARAVAN_VERSION_FILE=/home/bitcoin/.mynode/caravan_version
CARAVAN_LATEST_VERSION_FILE=/home/bitcoin/.mynode/caravan_version_latest

CORSPROXY_VERSION="v1.7.0"
CORSPROXY_VERSION_FILE=/home/bitcoin/.mynode/corsproxy_version
CORSPROXY_LATEST_VERSION_FILE=/home/bitcoin/.mynode/corsproxy_version_latest

JOINMARKET_VERSION="v0.8.2"
JOINMARKET_VERSION_FILE=/home/bitcoin/.mynode/joinmarket_version
JOINMARKET_LATEST_VERSION_FILE=/home/bitcoin/.mynode/joinmarket_version_latest

JOININBOX_VERSION="v0.2.0"
JOININBOX_VERSION_FILE=/home/bitcoin/.mynode/joininbox_version
JOININBOX_LATEST_VERSION_FILE=/home/bitcoin/.mynode/joininbox_version_latest

WHIRLPOOL_VERSION="0.10.9"
WHIRLPOOL_UPLOAD_FILE_ID="602666c59f95ce72f1466f72d9c853e3"
WHIRLPOOL_UPLOAD_SIG_ID="b072f024fad9609f3c659cd7620f51fa"
WHIRLPOOL_VERSION_FILE=/home/bitcoin/.mynode/whirlpool_version
WHIRLPOOL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/whirlpool_version_latest

RTL_VERSION="v0.10.1"
RTL_VERSION_FILE=/home/bitcoin/.mynode/rtl_version
RTL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/rtl_version_latest

BTCRPCEXPLORER_VERSION="v2.2.0"
BTCRPCEXPLORER_VERSION_FILE=/home/bitcoin/.mynode/btcrpcexplorer_version
BTCRPCEXPLORER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/btcrpcexplorer_version_latest

LNBITS_VERSION=503c981bc970f4ab894f50198dbd6833cae8f6e0         # Github hash to download
LNBITS_VERSION_FILE=/home/bitcoin/.mynode/lnbits_version
LNBITS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lnbits_version_latest

SPECTER_VERSION="1.2.2"
SPECTER_VERSION_FILE=/home/bitcoin/.mynode/specter_version
SPECTER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/specter_version_latest

THUNDERHUB_VERSION="v0.12.7"
THUNDERHUB_VERSION_FILE=/home/bitcoin/.mynode/thunderhub_version
THUNDERHUB_LATEST_VERSION_FILE=/home/bitcoin/.mynode/thunderhub_version_latest

LNDCONNECT_VERSION="v0.2.0"
LNDCONNECT_VERSION_FILE=/home/bitcoin/.mynode/lndconnect_version
LNDCONNECT_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lndconnect_version_latest

CKBUNKER_VERSION="v0.9"
CKBUNKER_VERSION_FILE=/home/bitcoin/.mynode/ckbunker_version
CKBUNKER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/ckbunker_version_latest

SPHINXRELAY_VERSION="v1.3.8"
SPHINXRELAY_VERSION_FILE=/home/bitcoin/.mynode/sphinxrelay_version
SPHINXRELAY_LATEST_VERSION_FILE=/home/bitcoin/.mynode/sphinxrelay_version_latest
