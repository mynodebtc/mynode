#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh

function get_app_version()
{
    local official_version=$1
    local short_name=$2
    local version=$official_version
    if [ -f "/home/bitcoin/.mynode/${short_name}_version_latest_custom" ]; then
        version=$(cat /home/bitcoin/.mynode/${short_name}_version_latest_custom)
    fi
    if [ -f "/mnt/hdd/mynode/settings/${short_name}_version_latest_custom" ]; then
        version=$(cat /mnt/hdd/mynode/settings/${short_name}_version_latest_custom)
    fi
    echo "$version"
}

function is_custom_app_version()
{
    local short_name=$1
    [ -f "/home/bitcoin/.mynode/${short_name}_version_latest_custom" ] || \
    [ -f "/mnt/hdd/mynode/settings/${short_name}_version_latest_custom" ]
}

# Check a download against a pinned "<version> <sha256>" value (see
# scripts/print_app_download_hashes.sh). Versions chosen by the user have no
# pinned hash and are not checked.
function check_app_download()
{
    local file=$1
    local short_name=$2
    local version=$3
    local pinned=$4
    local pinned_version=${pinned%% *}
    local pinned_hash=${pinned##* }

    if [ "$version" != "$pinned_version" ]; then
        if is_custom_app_version "$short_name"; then
            echo "Custom $short_name version $version, skipping download hash check"
            return 0
        fi
        echo "ERROR: no download hash for $short_name $version"
        return 1
    fi
    echo "$pinned_hash  $file" | sha256sum --check -
}

BTC_VERSION="29.3"
if [ "$DEBIAN_VERSION" -lt "12" ]; then
    BTC_VERSION="27.2"
fi
BTC_VERSION=$(get_app_version "$BTC_VERSION" "bitcoin")
BTC_VERSION_FILE=/home/bitcoin/.mynode/bitcoin_version
BTC_LATEST_VERSION_FILE=/home/bitcoin/.mynode/bitcoin_version_latest

LND_VERSION="v0.21.3-beta"
LND_VERSION=$(get_app_version "$LND_VERSION" "lnd")
LND_VERSION_FILE=/home/bitcoin/.mynode/lnd_version
LND_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lnd_version_latest
LND_UPGRADE_MANIFEST_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-$LND_VERSION.txt
LND_UPGRADE_MANIFEST_ROASBEEF_SIG_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-roasbeef-$LND_VERSION.sig
LND_UPGRADE_MANIFEST_GUGGERO_SIG_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-guggero-$LND_VERSION.sig
LND_UPGRADE_MANIFEST_SUHEB_SIG_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-suheb-$LND_VERSION.sig
LND_UPGRADE_MANIFEST_VICTORT_SIG_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-VictorT-11-$LND_VERSION.sig

LOOP_VERSION="v0.35.0-beta"
LOOP_VERSION=$(get_app_version "$LOOP_VERSION" "loop")
LOOP_VERSION_FILE=/home/bitcoin/.mynode/loop_version
LOOP_LATEST_VERSION_FILE=/home/bitcoin/.mynode/loop_version_latest
LOOP_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/manifest-$LOOP_VERSION.txt
LOOP_UPGRADE_MANIFEST_SIG_MODIFIER=""
LOOP_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/manifest$LOOP_UPGRADE_MANIFEST_SIG_MODIFIER-$LOOP_VERSION.txt.sig

POOL_VERSION="v0.6.4-beta"
POOL_VERSION=$(get_app_version "$POOL_VERSION" "pool")
POOL_VERSION_FILE=/home/bitcoin/.mynode/pool_version
POOL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/pool_version_latest
POOL_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/pool/releases/download/$POOL_VERSION/manifest-$POOL_VERSION.txt
POOL_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/pool/releases/download/$POOL_VERSION/manifest-$POOL_VERSION.sig

LIT_VERSION="v0.17.4-alpha"
LIT_VERSION=$(get_app_version "$LIT_VERSION" "lit")
LIT_VERSION_FILE=/home/bitcoin/.mynode/lit_version
LIT_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lit_version_latest
LIT_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/lightning-terminal/releases/download/$LIT_VERSION/manifest-$LIT_VERSION.txt
LIT_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/lightning-terminal/releases/download/$LIT_VERSION/manifest-ViktorT-11-$LIT_VERSION.sig

CHANTOOLS_VERSION="v0.11.3"
CHANTOOLS_VERSION=$(get_app_version "$CHANTOOLS_VERSION" "chantools")
CHANTOOLS_VERSION_FILE=/home/bitcoin/.mynode/chantools_version
CHANTOOLS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/chantools_version_latest
CHANTOOLS_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/chantools/releases/download/$CHANTOOLS_VERSION/manifest-$CHANTOOLS_VERSION.txt
CHANTOOLS_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/chantools/releases/download/$CHANTOOLS_VERSION/manifest-$CHANTOOLS_VERSION.sig

ELECTRS_VERSION="v0.10.9"
if [ "$IS_32_BIT" = "1" ]; then
    ELECTRS_VERSION="v0.9.9"
fi
ELECTRS_VERSION_FILE=/home/bitcoin/.mynode/electrs_version
ELECTRS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/electrs_version_latest

MEMPOOL_VERSION="v3.3.1"
if [ "$IS_32_BIT" = "1" ]; then
    MEMPOOL_VERSION="v2.3.1"
fi
MEMPOOL_VERSION=$(get_app_version "$MEMPOOL_VERSION" "mempool")
MEMPOOL_VERSION_FILE=/mnt/hdd/mynode/settings/mempool_version
MEMPOOL_LATEST_VERSION_FILE=/mnt/hdd/mynode/settings/mempool_version_latest

LNDHUB_VERSION="v1.4.1"
LNDHUB_SHA256="v1.4.1 913ab417607cffdadcf33eed41171036bf63e6aac2f26c54ad19e35b2cfce0dc"
LNDHUB_VERSION=$(get_app_version "$LNDHUB_VERSION" "lndhub")
LNDHUB_VERSION_FILE=/home/bitcoin/.mynode/lndhub_version
LNDHUB_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lndhub_version_latest

CARAVAN_VERSION="v0.6.2"
CARAVAN_SHA256="v0.6.2 07e955175403f2a3eac9ef02c4d88200265ee2d47b946023a659e5c92ab237d3"
CARAVAN_VERSION=$(get_app_version "$CARAVAN_VERSION" "caravan")
CARAVAN_SETTINGS_UPDATE_FILE=/home/bitcoin/.mynode/caravan_settings_1
CARAVAN_VERSION_FILE=/home/bitcoin/.mynode/caravan_version
CARAVAN_LATEST_VERSION_FILE=/home/bitcoin/.mynode/caravan_version_latest

CORSPROXY_VERSION="v1.7.0"
CORSPROXY_SHA256="v1.7.0 984f2f95297b4b098614b32712c359fb6de753ba51cba592560b7ecdd607bafd"
CORSPROXY_VERSION=$(get_app_version "$CORSPROXY_VERSION" "corsproxy")
CORSPROXY_VERSION_FILE=/home/bitcoin/.mynode/corsproxy_version
CORSPROXY_LATEST_VERSION_FILE=/home/bitcoin/.mynode/corsproxy_version_latest

JOININBOX_VERSION="v0.9.0"
JOININBOX_SHA256="v0.9.0 78a43ed498e656ccea7ca044df71445f12023642625db9865fc3cde182058c6a"
if [ "$DEBIAN_VERSION" -lt "12" ]; then
    JOININBOX_VERSION="v0.8.4"
    JOININBOX_SHA256="v0.8.4 151a786cee6bd6da22ca7bf8ab82beb7e27db301c5c810223538233121eacbc6"
fi
JOININBOX_VERSION=$(get_app_version "$JOININBOX_VERSION" "joininbox")
JOININBOX_VERSION_FILE=/home/bitcoin/.mynode/joininbox_version
JOININBOX_LATEST_VERSION_FILE=/home/bitcoin/.mynode/joininbox_version_latest

SECP256K1_VERSION=486205aa68b7f1d4291f78fa20bc4485fd843e1c
SECP256K1_VERSION_FILE=/home/bitcoin/.mynode/secp256k1_version
SECP256K1_LATEST_VERSION_FILE=/home/bitcoin/.mynode/secp256k1_version_latest

WHIRLPOOL_VERSION="0.10.16"
WHIRLPOOL_VERSION=$(get_app_version "$WHIRLPOOL_VERSION" "whirlpool")
WHIRLPOOL_UPLOAD_FILE_ID="63621e145967f536a562851853bd0990"
# Update sig file at /usr/share/whirlpool/whirlpool.asc for each release
WHIRLPOOL_VERSION_FILE=/home/bitcoin/.mynode/whirlpool_version
WHIRLPOOL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/whirlpool_version_latest

DOJO_VERSION="v1.20.0"
DOJO_VERSION=$(get_app_version "$DOJO_VERSION" "dojo")
# Find at https://code.samourai.io/dojo/samourai-dojo/-/releases in fingerprints
DOJO_TAR_HASH="747b2e8ff4c747a221c2de75ffcf28c54ebaa198f258fc372513142189b02360"
if [ "$IS_32_BIT" = "1" ]; then
    DOJO_VERSION="v1.14.0"
    DOJO_TAR_HASH="17aa26481e0a569719875687ed1744e3e45f3a7a70306298345d0a59acd17ad3"
fi
DOJO_VERSION_FILE=/mnt/hdd/mynode/settings/dojo_version
DOJO_LATEST_VERSION_FILE=/mnt/hdd/mynode/settings/dojo_version_latest

RTL_VERSION="v0.15.12"
if [ "$IS_32_BIT" = "1" ] || [ "$DEBIAN_VERSION" -lt "11" ]; then
    RTL_VERSION="v0.15.0"   # Newer versions require NodeJS 20.19+ (these devices stay on NodeJS 18)
fi
RTL_VERSION=$(get_app_version "$RTL_VERSION" "rtl")
RTL_VERSION_FILE=/home/bitcoin/.mynode/rtl_version
RTL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/rtl_version_latest

BTCPAYSERVER_VERSION="2.4.4"
if [ "$IS_32_BIT" = "1" ]; then
    BTCPAYSERVER_VERSION="1.3.6"
fi
BTCPAYSERVER_VERSION=$(get_app_version "$BTCPAYSERVER_VERSION" "btcpayserver")
BTCPAYSERVER_VERSION_FILE=/home/bitcoin/.mynode/btcpayserver_version
BTCPAYSERVER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/btcpayserver_version_latest

BTCRPCEXPLORER_VERSION="v3.5.1"
BTCRPCEXPLORER_SHA256="v3.5.1 731aa12573d541f00a27117784c86307c4c3833d27d2cf33565f71a34b3aa38f"
BTCRPCEXPLORER_VERSION=$(get_app_version "$BTCRPCEXPLORER_VERSION" "btcrpcexplorer")
BTCRPCEXPLORER_VERSION_FILE=/home/bitcoin/.mynode/btcrpcexplorer_version
BTCRPCEXPLORER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/btcrpcexplorer_version_latest

LNBITS_VERSION="v1.2.1"
LNBITS_VERSION=$(get_app_version "$LNBITS_VERSION" "lnbits")
LNBITS_VERSION_FILE=/home/bitcoin/.mynode/lnbits_version
LNBITS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lnbits_version_latest

SPECTER_VERSION="2.1.10"
if [ "$DEBIAN_VERSION" -lt "12" ]; then
    SPECTER_VERSION="1.14.1"
fi
SPECTER_VERSION=$(get_app_version "$SPECTER_VERSION" "specter")
SPECTER_VERSION_FILE=/home/bitcoin/.mynode/specter_version
SPECTER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/specter_version_latest

THUNDERHUB_VERSION="v0.14.6"
THUNDERHUB_SHA256="v0.14.6 3506bbc78b7fa1239e345fb5310722b868b8af0d9055b10a14710cbe3fd8953e"
THUNDERHUB_VERSION=$(get_app_version "$THUNDERHUB_VERSION" "thunderhub")
THUNDERHUB_VERSION_FILE=/home/bitcoin/.mynode/thunderhub_version
THUNDERHUB_LATEST_VERSION_FILE=/home/bitcoin/.mynode/thunderhub_version_latest

# Note: Newer versions won't be on pypi
LNDMANAGE_VERSION="0.14.2"
LNDMANAGE_VERSION=$(get_app_version "$LNDMANAGE_VERSION" "lndmanage")
LNDMANAGE_VERSION_FILE=/home/bitcoin/.mynode/lndmanage_version
LNDMANAGE_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lndmanage_version_latest

LNDCONNECT_VERSION="v0.2.0"
LNDCONNECT_VERSION=$(get_app_version "$LNDCONNECT_VERSION" "lndconnect")
LNDCONNECT_VERSION_FILE=/home/bitcoin/.mynode/lndconnect_version
LNDCONNECT_LATEST_VERSION_FILE=/home/bitcoin/.mynode/lndconnect_version_latest

CKBUNKER_VERSION="v0.9.mynode1"
CKBUNKER_SHA256="v0.9.mynode1 aeafbda6f9b6abb8f08fe48dbc0b0b83c110714413dfe51ff83b47e80578cc72"
CKBUNKER_VERSION=$(get_app_version "$CKBUNKER_VERSION" "ckbunker")
CKBUNKER_VERSION_FILE=/home/bitcoin/.mynode/ckbunker_version
CKBUNKER_LATEST_VERSION_FILE=/home/bitcoin/.mynode/ckbunker_version_latest
CKBUNKER_UPGRADE_URL=https://github.com/Coldcard/ckbunker/archive/ae87d17bdaa049e9ca85e706f1facf46a1552448.tar.gz

BOS_VERSION="13.31.5"
BOS_VERSION=$(get_app_version "$BOS_VERSION" "bos")
BOS_VERSION_FILE=/home/bitcoin/.mynode/bos_version
BOS_LATEST_VERSION_FILE=/home/bitcoin/.mynode/bos_version_latest

SPHINXRELAY_VERSION="v2.5.3"
SPHINXRELAY_SHA256="v2.5.3 264fe2fd6b734a5744d3cdab22afe3858a88b798e3de9a94a8bb20bb0777e354"
SPHINXRELAY_VERSION=$(get_app_version "$SPHINXRELAY_VERSION" "sphinxrelay")
SPHINXRELAY_VERSION_FILE=/home/bitcoin/.mynode/sphinxrelay_version
SPHINXRELAY_LATEST_VERSION_FILE=/home/bitcoin/.mynode/sphinxrelay_version_latest

PYBLOCK_VERSION="v1.1.9"
PYBLOCK_SHA256="v1.1.9 f4dcfc632f248109b5dd0cee03ca37e46ad273ec75a08aff16cde21d9e68df93"
PYBLOCK_VERSION=$(get_app_version "$PYBLOCK_VERSION" "pyblock")
PYBLOCK_VERSION_FILE=/home/bitcoin/.mynode/pyblock_version
PYBLOCK_LATEST_VERSION_FILE=/home/bitcoin/.mynode/pyblock_version_latest

WARDENTERMINAL_VERSION="869bb48453e9444691c27d2c8908abf2694094ea"
WARDENTERMINAL_SHA256="869bb48453e9444691c27d2c8908abf2694094ea 009050f5f34b1a1f4d95acb3cd439deb9ea67075c4636a4cf6602fc0644894d3"
WARDENTERMINAL_VERSION=$(get_app_version "$WARDENTERMINAL_VERSION" "wardenterminal")
WARDENTERMINAL_VERSION_FILE=/home/bitcoin/.mynode/wardenterminal_version
WARDENTERMINAL_LATEST_VERSION_FILE=/home/bitcoin/.mynode/wardenterminal_version_latest

LOG2RAM_VERSION="v1.2.2"
LOG2RAM_SHA256="v1.2.2 60423549533fc6eb1bc02743cbeda300eb0666b30e782d5701834c8e04324299"

NETDATA_VERSION="v1.32.1"
NETDATA_VERSION=$(get_app_version "$NETDATA_VERSION" "netdata")
NETDATA_VERSION_FILE=/mnt/hdd/mynode/settings/netdata_version
NETDATA_LATEST_VERSION_FILE=/mnt/hdd/mynode/settings/netdata_version_latest

WEBSSH2_VERSION="v0.2.10-0"
WEBSSH2_VERSION=$(get_app_version "$WEBSSH2_VERSION" "webssh2")
WEBSSH2_VERSION_FILE=/mnt/hdd/mynode/settings/webssh2_version
WEBSSH2_LATEST_VERSION_FILE=/mnt/hdd/mynode/settings/webssh2_version_latest

RATHOLE_VERSION="v0.4.7"
RATHOLE_VERSION=$(get_app_version "$RATHOLE_VERSION" "rathole")
RATHOLE_VERSION_FILE=/home/bitcoin/.mynode/rathole_version
RATHOLE_LATEST_VERSION_FILE=/home/bitcoin/.mynode/rathole_version_latest

# Dependency versions
PYTHON_VERSION="3.8.9"
#PYTHON_VERSION="3.11.14"   # New python needed once JoinMarket goes past v0.9.11
if [ "$DEBIAN_VERSION" -lt "12" ]; then
    PYTHON_VERSION="3.8.9"
fi

PYTHON_ARM32_GRPCIO_VERSION="1.40.0"

NODE_JS_VERSION="24.x"
if [ "$IS_32_BIT" = "1" ]; then
    NODE_JS_VERSION="18.x"
fi
if [ "$DEBIAN_VERSION" -lt "11" ]; then
    NODE_JS_VERSION="18.x"
fi
NODE_JS_VERSION=$(get_app_version "$NODE_JS_VERSION" "nodejs")

RUST_VERSION="1.86.0"

GO_VERSION="1.19.4"
GO_VERSION_FILE=/home/bitcoin/.mynode/go_version

# Check for override files
if [ -f /usr/share/mynode/mynode_app_versions_custom.sh ]; then
    source /usr/share/mynode/mynode_app_versions_custom.sh
elif [ -f /mnt/hdd/mynode/settings/mynode_app_versions_custom.sh ]; then
    source /mnt/hdd/mynode/settings/mynode_app_versions_custom.sh
fi
