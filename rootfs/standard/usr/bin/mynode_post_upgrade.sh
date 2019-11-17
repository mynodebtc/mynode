#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x
set -e

# Shut down main services to save memory and CPU
systemctl stop electrs
systemctl stop lnd
systemctl stop quicksync
systemctl stop bitcoind

# Install any new software
apt -y install pv sysstat network-manager unzip pkg-config libfreetype6-dev libpng-dev
apt -y install libatlas-base-dev libffi-dev libssl-dev glances python3-bottle

# Install any pip software
pip install tzupdate


# Install any pip3 software
pip3 install python-bitcointx
pip3 install lndmanage==0.8.0   # Install LND Manage (keep up to date with LND)
pip3 install docker-compose


# Import Keys
curl https://keybase.io/roasbeef/pgp_keys.asc | gpg --import
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964


# Install docker
if [ ! -f /usr/bin/docker ]; then
    curl -sSL https://get.docker.com | sh
fi
groupadd docker || true
usermod -aG docker admin
usermod -aG docker bitcoin
usermod -aG docker root

## Install BTCPay and its dependencies
#- install Postgres database
apt -y install postgresql postgresql-contrib
#- Download .NET binaries
cd /opt/mynode
sudo -u bitcoin mkdir -p dotnet-2.1 dotnet-3.0
cd dotnet-3.0
sudo -u bitcoin wget https://download.visualstudio.microsoft.com/download/pr/8ddb8193-f88c-4c4b-82a3-39fcced27e91/b8e0b9bf4cf77dff09ff86cc1a73960b/dotnet-sdk-3.0.100-linux-arm.tar.gz
sudo -u bitcoin tar -xf dotnet-sdk-3.0.100-linux-arm.tar.gz
sudo -u bitcoin rm dotnet-sdk-3.0.100-linux-arm.tar.gz
cd ../dotnet-2.1
sudo -u bitcoin wget https://download.visualstudio.microsoft.com/download/pr/516cf8d3-f536-4f58-a5ce-aa6f2f85d1c8/98aab0aaedd12e987310f4c2c1f327d3/dotnet-sdk-2.1.802-linux-arm.tar.gz
sudo -u bitcoin tar -xf dotnet-sdk-2.1.802-linux-arm.tar.gz
sudo -u bitcoin rm dotnet-sdk-2.1.802-linux-arm.tar.gz
cd ..
#- Install NBXplorer
sudo -u bitcoin rm -rf NBXplorer
sudo -u bitcoin git clone https://github.com/dgarage/NBXplorer
cd NBXplorer
sudo -u bitcoin rm build.sh
export DOTNET_ROOT=/opt/mynode/dotnet-3.0
sudo -u bitcoin /opt/mynode/dotnet-3.0/dotnet build -c Release NBXplorer/NBXplorer.csproj
sudo -u bitcoin rm run.sh
sudo -u bitcoin touch run.sh
sudo -u bitcoin echo "#!/bin/bash" > run.sh
sudo -u bitcoin echo "export DOTNET_ROOT=/opt/mynode/dotnet-3.0" >> run.sh
sudo -u bitcoin echo '$DOTNET_ROOT/dotnet run --no-launch-profile --no-build -c Release -p "NBXplorer/NBXplorer.csproj" -- $@' >> run.sh
sudo -u bitcoin chmod +x run.sh
cd ..
#- Install BTCPay server
sudo -u bitcoin rm -rf btcpayserver
sudo -u bitcoin git clone https://github.com/btcpayserver/btcpayserver
cd btcpayserver
sudo -u bitcoin /opt/mynode/dotnet-2.1/dotnet build -c Release BTCPayServer/BTCPayServer.csproj
sudo -u bitcoin rm run.sh
sudo -u bitcoin touch run.sh
sudo -u bitcoin echo "#!/bin/bash" > run.sh
sudo -u bitcoin echo '/opt/mynode/dotnet-2.1/dotnet run --no-launch-profile --no-build -c Release -p "BTCPayServer/BTCPayServer.csproj" -- $@' >> run.sh
sudo -u bitcoin chmod +x run.sh
cd ..


# Upgrade BTC
set +e
BTC_VERSION="0.18.1"
ARCH="arm-linux-gnueabihf"
uname -a | grep aarch64
if [ $? = 0 ]; then
    ARCH="aarch64-linux-gnu"
fi
if [ $IS_X86 = 1 ]; then
    ARCH="x86_64-linux-gnu" 
fi
set -e
BTC_UPGRADE_URL=https://bitcoincore.org/bin/bitcoin-core-$BTC_VERSION/bitcoin-$BTC_VERSION-$ARCH.tar.gz
BTC_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.btc_url
BTC_UPGRADE_SHA256SUM_URL=https://bitcoincore.org/bin/bitcoin-core-$BTC_VERSION/SHA256SUMS.asc
CURRENT=""
if [ -f $BTC_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $BTC_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$BTC_UPGRADE_URL" ]; then
    # Download and install Bitcoin
    rm -rf /tmp/download
    mkdir -p /tmp/download
    cd /tmp/download

    wget $BTC_UPGRADE_URL
    wget $BTC_UPGRADE_SHA256SUM_URL -O SHA256SUMS.asc

    sha256sum --ignore-missing --check SHA256SUMS.asc
    if [ $? == 0 ]; then
        gpg --verify SHA256SUMS.asc
        if [ $? == 0 ]; then
            # Install Bitcoin
            tar -xvf bitcoin-$BTC_VERSION-$ARCH.tar.gz
            mv bitcoin-$BTC_VERSION bitcoin
            install -m 0755 -o root -g root -t /usr/local/bin bitcoin/bin/*

            # Mark current version
            echo $BTC_UPGRADE_URL > $BTC_UPGRADE_URL_FILE
        else
            echo "ERROR UPGRADING BITCOIN - GPG FAILED"
        fi
    else
        echo "ERROR UPGRADING BITCOIN - SHASUM FAILED"
    fi
fi

# Upgrade LND
LND_VERSION="v0.8.0-beta"
LND_ARCH="lnd-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LND_ARCH="lnd-linux-amd64"
fi
LND_UPGRADE_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/$LND_ARCH-$LND_VERSION.tar.gz
LND_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.lnd_url
LND_UPGRADE_MANIFEST_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-$LND_VERSION.txt
LND_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-$LND_VERSION.txt.sig
CURRENT=""
if [ -f $LND_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $LND_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$LND_UPGRADE_URL" ]; then
    # Download and install LND
    rm -rf /tmp/download
    mkdir -p /tmp/download
    cd /tmp/download

    wget $LND_UPGRADE_URL
    wget $LND_UPGRADE_MANIFEST_URL
    wget $LND_UPGRADE_MANIFEST_SIG_URL

    gpg --verify manifest-*.txt.sig
    if [ $? == 0 ]; then
        # Install LND
        tar -xzf lnd-*.tar.gz
        mv $LND_ARCH-$LND_VERSION lnd
        install -m 0755 -o root -g root -t /usr/local/bin lnd/*

        # Mark current version
        echo $LND_UPGRADE_URL > $LND_UPGRADE_URL_FILE
    else
        echo "ERROR UPGRADING LND - GPG FAILED"
    fi
fi

# Upgrade RTL
RTL_UPGRADE_URL=https://github.com/ShahanaFarooqui/RTL/archive/v0.5.1.tar.gz
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
    sudo -u bitcoin NG_CLI_ANALYTICS=false npm install
    
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
BTCRPCEXPLORER_UPGRADE_URL=https://github.com/janoside/btc-rpc-explorer/archive/v1.1.1.tar.gz
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

# Install ngrok for debugging
if [ ! -f /usr/bin/ngrok  ]; then
    cd /tmp
    rm -rf /tmp/ngrok*
    NGROK_URL=https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-arm.zip
    if [ $IS_X86 = 1 ]; then
        NGROK_URL=https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-386.zip
    fi
    wget $NGROK_URL
    unzip ngrok-*.zip
    cp ngrok /usr/bin/
fi

# Enable any new/required services
systemctl enable firewall
systemctl enable invalid_block_check
systemctl enable usb_driver_check
systemctl enable https
systemctl enable glances
systemctl enable netdata
systemctl enable nbxplorer
systemctl enable btcpay

# Disable any old services
sudo systemctl disable hitch
sudo systemctl disable mongodb
sudo systemctl disable lnd_admin

# Reload service settings
systemctl daemon-reload

# Sync FS
sync