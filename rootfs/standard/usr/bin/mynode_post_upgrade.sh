#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x
set -e

# Make sure time is in the log
date

# Shut down main services to save memory and CPU
/usr/bin/mynode_stop_critical_services.sh

# Delete ramlog to prevent ram issues
rm -rf /var/log/*

# Check if any dpkg installs have failed and correct
dpkg --configure -a


# Add sources
apt-get -y install apt-transport-https
DEBIAN_VERSION=$(lsb_release -c | awk '{ print $2 }')
grep -qxF "deb https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
grep -qxF "deb-src https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb-src https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" >> /etc/apt/sources.list


# Import Keys
set +e
curl https://keybase.io/roasbeef/pgp_keys.asc | gpg --import
curl https://raw.githubusercontent.com/JoinMarket-Org/joinmarket-clientserver/master/pubkeys/AdamGibson.asc | gpg --import
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964
curl https://keybase.io/suheb/pgp_keys.asc | gpg --import
gpg  --keyserver hkps://keyserver.ubuntu.com --recv-keys DE23E73BFA8A0AD5587D2FCDE80D2F3F311FD87E #loopd
curl https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --import  # tor
gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -                                       # tor
set -e


# Check for updates (might auto-install all updates later)
apt-get update


# Install any new software
export DEBIAN_FRONTEND=noninteractive
apt-get -y install apt-transport-https
apt-get -y install fonts-dejavu
apt-get -y install pv sysstat network-manager unzip pkg-config libfreetype6-dev libpng-dev
apt-get -y install libatlas-base-dev libffi-dev libssl-dev glances python3-bottle
apt-get -y -qq install apt-transport-https ca-certificates
apt-get -y install libgmp-dev automake libtool libltdl-dev libltdl7
apt-get -y install xorg chromium openbox lightdm openjdk-11-jre libevent-dev ncurses-dev

# Make sure some software is removed
apt-get -y purge ntp # (conflicts with systemd-timedatectl)
apt-get -y purge chrony # (conflicts with systemd-timedatectl)


# Install any pip software
pip install tzupdate virtualenv --no-cache-dir


# Install any pip3 software
pip3 install python-bitcointx --no-cache-dir
pip3 install gnureadline --no-cache-dir
pip3 install lndmanage==0.9.0 --no-cache-dir   # Install LND Manage (keep up to date with LND)
pip3 install docker-compose --no-cache-dir


# Install docker
if [ ! -f /usr/bin/docker ]; then
    rm -f /tmp/docker_install.sh
    wget https://get.docker.com -O /tmp/docker_install.sh
    sed -i 's/sleep 20/sleep 1/' /tmp/docker_install.sh
    /bin/bash /tmp/docker_install.sh
fi

# Use systemd for managing docker
rm -f /etc/init.d/docker
rm -f /etc/systemd/system/multi-user.target.wants/docker.service
systemctl -f enable docker.service

groupadd docker || true
usermod -aG docker admin
usermod -aG docker bitcoin
usermod -aG docker root


# Install node packages


# Upgrade BTC
echo "Upgrading BTC..."
BTC_VERSION="0.19.0.1"
ARCH="UNKNOWN"
if [ $IS_RASPI = 1 ]; then
    ARCH="arm-linux-gnueabihf"
elif [ $IS_ROCK64 = 1 ] || [ $IS_ROCKPRO64 = 1 ]; then
    ARCH="aarch64-linux-gnu"
elif [ $IS_X86 = 1 ]; then
    ARCH="x86_64-linux-gnu" 
else
    echo "Unknown Bitcoin Version"
    exit 1
fi
BTC_UPGRADE_URL=https://bitcoincore.org/bin/bitcoin-core-$BTC_VERSION/bitcoin-$BTC_VERSION-$ARCH.tar.gz
BTC_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.btc_url
BTC_UPGRADE_SHA256SUM_URL=https://bitcoincore.org/bin/bitcoin-core-$BTC_VERSION/SHA256SUMS.asc
CURRENT=""
if [ -f $BTC_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $BTC_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$BTC_UPGRADE_URL" ]; then
    # Download and install Bitcoin
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download

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
echo "Upgrading LND..."
LND_VERSION="v0.9.0-beta"
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
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download

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

# Upgrade Loopd
echo "Upgrading loopd..."
LOOP_VERSION="v0.4.0-beta"
LOOP_ARCH="loop-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LOOP_ARCH="loop-linux-amd64"
fi
LOOP_UPGRADE_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/$LOOP_ARCH-$LOOP_VERSION.tar.gz
LOOP_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.loop_url
LOOP_UPGRADE_MANIFEST_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/manifest-$LOOP_VERSION.txt
LOOP_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/manifest-$LOOP_VERSION.txt.sig
CURRENT=""
if [ -f $LOOP_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $LOOP_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$LOOP_UPGRADE_URL" ]; then
    # Download and install Loop
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download

    wget $LOOP_UPGRADE_URL
    wget $LOOP_UPGRADE_MANIFEST_URL
    wget $LOOP_UPGRADE_MANIFEST_SIG_URL

    gpg --verify manifest-*.txt.sig
    if [ $? == 0 ]; then
        # Install Loop
        tar -xzf loop-*.tar.gz
        mv $LOOP_ARCH-$LOOP_VERSION loop
        install -m 0755 -o root -g root -t /usr/local/bin loop/*

        # Mark current version
        echo $LOOP_UPGRADE_URL > $LOOP_UPGRADE_URL_FILE
    else
        echo "ERROR UPGRADING LND - GPG FAILED"
    fi
fi

# Install LndHub
LNDHUB_VERSION="v1.1.3"
LNDHUB_UPGRADE_URL=https://github.com/BlueWallet/LndHub/archive/${LNDHUB_VERSION}.tar.gz
LNDHUB_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.lndhub_url
CURRENT=""
if [ -f $LNDHUB_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $LNDHUB_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$LNDHUB_UPGRADE_URL" ]; then
    cd /opt/mynode
    rm -rf LndHub

    wget $LNDHUB_UPGRADE_URL
    tar -xzf ${LNDHUB_VERSION}.tar.gz
    rm -f ${LNDHUB_VERSION}.tar.gz
    mv LndHub-* LndHub
    chown -R bitcoin:bitcoin LndHub

    cd LndHub
    sudo -u bitcoin npm install --only=production
    sudo -u bitcoin ln -s /home/bitcoin/.lnd/tls.cert tls.cert
    sudo -u bitcoin ln -s /home/bitcoin/.lnd/data/chain/bitcoin/mainnet/admin.macaroon admin.macaroon
    echo $LNDHUB_UPGRADE_URL > $LNDHUB_UPGRADE_URL_FILE
fi
cd ~

# Install recent version of secp256k1
echo "Installing secp256k1..."
if [ ! -f /usr/include/secp256k1_ecdh.h ]; then
    rm -rf /tmp/secp256k1
    cd /tmp/
    git clone https://github.com/bitcoin-core/secp256k1.git
    cd secp256k1

    ./autogen.sh
    ./configure
    make
    make install
    cp -f include/* /usr/include/
fi

# Upgrade Joinmarket
echo "Upgrading JoinMarket..."
if [ $IS_PREMIUM -eq 1 ]; then
    JOINMARKET_VERSION=0.6.1
    JOINMARKET_GITHUB_URL=https://github.com/JoinMarket-Org/joinmarket-clientserver.git
    JOINMARKET_VERSION_FILE=/home/bitcoin/.mynode/.joinmarket_version
    CURRENT=""
    if [ -f $JOINMARKET_VERSION_FILE ]; then
        CURRENT=$(cat $JOINMARKET_VERSION_FILE)
    fi
    if [ "$CURRENT" != "$JOINMARKET_VERSION" ]; then
        # Download and build JoinMarket
        cd /opt/mynode

        if [ ! -d /opt/mynode/joinmarket-clientserver ]; then
            git clone $JOINMARKET_GITHUB_URL
            cd joinmarket-clientserver
        else
            cd joinmarket-clientserver
            git pull origin master
        fi
        git fetch --tags --all
        git reset --hard v$JOINMARKET_VERSION

        # Create virtualenv and setup joinmarket
        virtualenv -p python3 jmvenv
        source jmvenv/bin/activate
        python setupall.py --daemon
        python setupall.py --client-bitcoin
        deactivate

        echo $JOINMARKET_VERSION > $JOINMARKET_VERSION_FILE
    fi
fi

# Install Whirlpool
WHIRLPOOL_UPGRADE_URL=https://github.com/Samourai-Wallet/whirlpool-client-cli/releases/download/0.10.2/whirlpool-client-cli-0.10.2-run.jar
WHIRLPOOL_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.whirlpool_url
CURRENT=""
if [ -f $WHIRLPOOL_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $WHIRLPOOL_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$WHIRLPOOL_UPGRADE_URL" ]; then
    sudo -u bitcoin mkdir -p /opt/mynode/whirlpool
    cd /opt/mynode/whirlpool
    sudo rm -rf *.jar
    sudo -u bitcoin wget -O whirlpool.jar $WHIRLPOOL_UPGRADE_URL
    
    echo $WHIRLPOOL_UPGRADE_URL > $WHIRLPOOL_UPGRADE_URL_FILE
fi

# Upgrade RTL
RTL_VERSION="v0.6.7"
RTL_UPGRADE_URL=https://github.com/Ride-The-Lightning/RTL/archive/$RTL_VERSION.tar.gz
RTL_UPGRADE_ASC_URL=https://github.com/Ride-The-Lightning/RTL/releases/download/$RTL_VERSION/$RTL_VERSION.tar.gz.asc
RTL_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.rtl_url
CURRENT=""
if [ -f $RTL_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $RTL_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$RTL_UPGRADE_URL" ]; then
    cd /opt/mynode
    rm -rf RTL

    sudo -u bitcoin wget $RTL_UPGRADE_URL -O RTL.tar.gz
    #sudo -u bitcoin wget $RTL_UPGRADE_ASC_URL -O RTL.tar.gz.asc

    #gpg --verify RTL.tar.gz.asc RTL.tar.gz
    #if [ $? == 0 ]; then
    if [ true ]; then
        sudo -u bitcoin tar -xvf RTL.tar.gz
        sudo -u bitcoin rm RTL.tar.gz
        sudo -u bitcoin mv RTL-* RTL
        cd RTL
        sudo -u bitcoin NG_CLI_ANALYTICS=false npm install --only=production
        
        mkdir -p /home/bitcoin/.mynode/
        chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
        echo $RTL_UPGRADE_URL > $RTL_UPGRADE_URL_FILE
    else
        echo "ERROR UPGRADING RTL - GPG FAILED"
    fi
fi

# Upgrade Bitcoin RPC Explorer
BTCRPCEXPLORER_UPGRADE_URL=https://github.com/janoside/btc-rpc-explorer/archive/v1.1.8.tar.gz
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
    sudo -u bitcoin npm install --only=production

    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $BTCRPCEXPLORER_UPGRADE_URL > $BTCRPCEXPLORER_UPGRADE_URL_FILE
fi


# Install LND Connect
LNDCONNECTARCH="lndconnect-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LNDCONNECTARCH="lndconnect-linux-amd64"
fi
LNDCONNECT_UPGRADE_URL=https://github.com/LN-Zap/lndconnect/releases/download/v0.2.0/$LNDCONNECTARCH-v0.2.0.tar.gz
LNDCONNECT_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.lndconnect_url
CURRENT=""
if [ -f $LNDCONNECT_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $LNDCONNECT_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$LNDCONNECT_UPGRADE_URL" ]; then
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download
    wget $LNDCONNECT_UPGRADE_URL -O lndconnect.tar.gz
    tar -xvf lndconnect.tar.gz
    rm lndconnect.tar.gz
    mv lndconnect-* lndconnect
    install -m 0755 -o root -g root -t /usr/local/bin lndconnect/* 

    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $LNDCONNECT_UPGRADE_URL > $LNDCONNECT_UPGRADE_URL_FILE
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

# Install recent version of tor
# echo "Installing tor..."
# TOR_UPGRADE_URL=https://dist.torproject.org/tor-0.4.2.5.tar.gz
# TOR_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.tor_url
# CURRENT=""
# if [ -f $TOR_UPGRADE_URL_FILE ]; then
#     CURRENT=$(cat $TOR_UPGRADE_URL_FILE)
# fi
# if [ "$CURRENT" != "$TOR_UPGRADE_URL" ]; then
#     rm -rf /opt/download
#     mkdir -p /opt/download
#     cd /opt/download
#     wget $TOR_UPGRADE_URL -O tor.tar.gz
#     tar -xvf tor.tar.gz
#     rm tor.tar.gz
#     mv tor-* tor
    
#     cd tor
#     ./configure
#     make
#     make install

#     echo $TOR_UPGRADE_URL > $TOR_UPGRADE_URL_FILE
# fi
rm -f /usr/local/bin/tor || true
apt-get remove -y tor	
apt-get install -y tor

# Enable fan control
if [ $IS_ROCKPRO64 = 1 ]; then
    systemctl enable fan_control
fi


# Enable any new/required services
systemctl enable firewall
systemctl enable invalid_block_check
systemctl enable usb_driver_check
systemctl enable https
systemctl enable docker_images
systemctl enable glances
systemctl enable netdata
systemctl enable webssh2
systemctl enable tor
systemctl enable loopd
systemctl enable rotate_logs

# Disable any old services
systemctl disable hitch || true
systemctl disable mongodb || true
systemctl disable lnd_admin || true
systemctl disable dhcpcd || true

# Reload service settings
systemctl daemon-reload

# Sync FS
sync
