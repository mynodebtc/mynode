#!/bin/bash

source /usr/share/mynode/mynode_config.sh

# Install any new software
# apt-get -y install ...

# Install any pip software
# ...

# Upgrade BTC
ARCH="arm-linux-gnueabihf"
uname -a | grep aarch64
if [ $? = 0 ]; then
    ARCH="aarch64-linux-gnu"
fi
BTC_UPGRADE_URL=https://bitcoin.org/bin/bitcoin-core-0.18.0/bitcoin-0.18.0-$ARCH.tar.gz
BTC_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.btc_url
CURRENT=""
if [ -f $BTC_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $BTC_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$BTC_UPGRADE_URL" ]; then
    # Download and install Bitcoin
    rm -rf /tmp/bitcoin*
    cd /tmp
    wget $BTC_UPGRADE_URL -O bitcoin.tar.gz
    tar -xvf bitcoin.tar.gz
    mv bitcoin-* bitcoin
    install -m 0755 -o root -g root -t /usr/local/bin bitcoin/bin/*

    # Mark current version
    echo $BTC_UPGRADE_URL > $BTC_UPGRADE_URL_FILE
fi

# Upgrade LND
LND_UPGRADE_URL=https://github.com/lightningnetwork/lnd/releases/download/v0.7.0-beta/lnd-linux-armv7-v0.7.0-beta.tar.gz
LND_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.lnd_url
CURRENT=""
if [ -f $LND_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $LND_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$LND_UPGRADE_URL" ]; then
    # Download and install LND
    rm -rf /tmp/lnd*
    cd /tmp
    wget $LND_UPGRADE_URL -O lnd.tar.gz
    tar -xzf lnd.tar.gz
    mv lnd-* lnd
    install -m 0755 -o root -g root -t /usr/local/bin lnd/*

    # Mark current version
    echo $LND_UPGRADE_URL > $LND_UPGRADE_URL_FILE
fi

# Enable any new/required services
# systemctl enable ...

# Reload service settings
systemctl daemon-reload

# Sync FS
sync