#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x

# Shut down main services to save memory and CPU
systemctl stop bitcoind
systemctl stop lnd
systemctl stop electrs
systemctl stop quicksync

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

# Upgrade RTL
RTL_UPGRADE_URL=https://github.com/ShahanaFarooqui/RTL/archive/v0.4.4.tar.gz
RTL_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.rtl_url
CURRENT=""
if [ -f $RTL_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $RTL_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$RTL_UPGRADE_URL" ]; then
    cd /opt/mynode
    rm -rf RTL
    sudo -u bitcoin wget $RTL_UPGRADE_URL -O RTL.tar.gz
    sudo -u bitcoin tar -xvf RTL.tar.gz
    sudo -u bitcoin rm RTL.tar.gz
    sudo -u bitcoin mv RTL-* RTL
    cd RTL
    sudo -u bitcoin npm install
    
    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $RTL_UPGRADE_URL > $RTL_UPGRADE_URL_FILE
fi

# Upgrade LND Admin
LNDADMIN_UPGRADE_URL=https://github.com/janoside/lnd-admin/archive/v0.10.12.tar.gz
LNDADMIN_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.lndadmin_url
CURRENT=""
if [ -f $LNDADMIN_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $LNDADMIN_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$LNDADMIN_UPGRADE_URL" ]; then
    cd /opt/mynode
    rm -rf lnd-admin
    sudo -u bitcoin wget $LNDADMIN_UPGRADE_URL -O lnd-admin.tar.gz
    sudo -u bitcoin tar -xvf lnd-admin.tar.gz
    sudo -u bitcoin rm lnd-admin.tar.gz
    sudo -u bitcoin mv lnd-* lnd-admin
    cd lnd-admin
    sudo -u bitcoin npm install

    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $LNDADMIN_UPGRADE_URL > $LNDADMIN_UPGRADE_URL_FILE
fi

# Upgrade Bitcoin RPC Explorer
BTCRPCEXPLORER_UPGRADE_URL=https://github.com/janoside/btc-rpc-explorer/archive/v1.0.3.tar.gz
BTCRPCEXPLORER_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.btcrpcexplorer_url
CURRENT=""
if [ -f $BTCRPCEXPLORER_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $BTCRPCEXPLORER_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$BTCRPCEXPLORER_UPGRADE_URL" ]; then
    cd /opt/mynode
    rm -rf btc-rpc-explorer
    sudo -u bitcoin wget $BTCRPCEXPLORER_UPGRADE_URL -O btc-rpc-explorer.tar.gz
    sudo -u bitcoin tar -xvf btc-rpc-explorer.tar.gz
    sudo -u bitcoin rm btc-rpc-explorer.tar.gz
    sudo -u bitcoin mv btc-rpc-* btc-rpc-explorer
    cd btc-rpc-explorer
    sudo -u bitcoin npm install

    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $BTCRPCEXPLORER_UPGRADE_URL > $BTCRPCEXPLORER_UPGRADE_URL_FILE
fi


# Enable any new/required services
# systemctl enable ...

# Reload service settings
systemctl daemon-reload

# Sync FS
sync