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

# Create any necessary users


# Check if upgrades use tor
TORIFY=""
if [ -f /mnt/hdd/mynode/settings/torify_apt_get ]; then
    TORIFY="torify"
fi

# Check if any dpkg installs have failed and correct
dpkg --configure -a


# Add sources
apt-get -y install apt-transport-https
DEBIAN_VERSION=$(lsb_release -c | awk '{ print $2 }')
# Tor
grep -qxF "deb https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
grep -qxF "deb-src https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb-src https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
# Raspbian mirrors
if [ $IS_RASPI = 1 ]; then
    grep -qxF "deb http://plug-mirror.rcac.purdue.edu/raspbian/ ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb http://plug-mirror.rcac.purdue.edu/raspbian/ ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
    grep -qxF "deb http://mirrors.ocf.berkeley.edu/raspbian/raspbian ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb http://mirrors.ocf.berkeley.edu/raspbian/raspbian ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
fi

# Import Keys
set +e
curl https://keybase.io/roasbeef/pgp_keys.asc | gpg --import
curl https://raw.githubusercontent.com/JoinMarket-Org/joinmarket-clientserver/master/pubkeys/AdamGibson.asc | gpg --import
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964
curl https://keybase.io/suheb/pgp_keys.asc | gpg --import
gpg  --keyserver hkps://keyserver.ubuntu.com --recv-keys DE23E73BFA8A0AD5587D2FCDE80D2F3F311FD87E #loopd
$TORIFY curl https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --import  # tor
gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -                                       # tor
set -e


# Check for updates (might auto-install all updates later)
export DEBIAN_FRONTEND=noninteractive
$TORIFY apt-get update
$TORIFY apt-get -y upgrade

# Install any new software
$TORIFY apt-get -y install apt-transport-https
$TORIFY apt-get -y install fonts-dejavu
$TORIFY apt-get -y install pv sysstat network-manager unzip pkg-config libfreetype6-dev libpng-dev
$TORIFY apt-get -y install libatlas-base-dev libffi-dev libssl-dev glances python3-bottle
$TORIFY apt-get -y -qq install apt-transport-https ca-certificates
$TORIFY apt-get -y install libgmp-dev automake libtool libltdl-dev libltdl7
$TORIFY apt-get -y install xorg chromium openbox lightdm openjdk-11-jre libevent-dev ncurses-dev
$TORIFY apt-get -y install libudev-dev libusb-1.0-0-dev python3-venv gunicorn libsqlite3-dev
$TORIFY apt-get -y install torsocks python3-requests

# Make sure some software is removed
apt-get -y purge ntp # (conflicts with systemd-timedatectl)
apt-get -y purge chrony # (conflicts with systemd-timedatectl)


# Install nginx
mkdir -p /var/log/nginx || true
$TORIFY apt-get -y install nginx || true
# Install may fail, so we need to edit the default config file and reconfigure
echo "" > /etc/nginx/sites-available/default
dpkg --configure -a

# Install any pip software
pip2 install tzupdate virtualenv pysocks --no-cache-dir


# Update Python3 to 3.7.X
PYTHON_VERSION=3.7.7
CURRENT_PYTHON3_VERSION=$(python3 --version)
if [[ "$CURRENT_PYTHON3_VERSION" != *"Python ${PYTHON_VERSION}"* ]]; then
    mkdir -p /opt/download
    cd /opt/download
    rm -rf Python-*

    wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz -O python.tar.xz
    tar xf python.tar.xz

    cd Python-*
    ./configure
    make -j4
    make install
    cd ~
else
    echo "Python up to date"
fi


# Install any pip3 software
pip3 install gnureadline --no-cache-dir
pip3 install lndmanage==0.10.0 --no-cache-dir   # Install LND Manage (keep up to date with LND)
pip3 install docker-compose --no-cache-dir
pip3 install pipenv --no-cache-dir
pip3 install bcrypt --no-cache-dir
pip3 install pysocks --no-cache-dir


# Install Docker
if [ ! -f /usr/bin/docker ]; then
    rm -f /tmp/docker_install.sh
    wget https://get.docker.com -O /tmp/docker_install.sh
    sed -i 's/sleep 20/sleep 1/' /tmp/docker_install.sh
    /bin/bash /tmp/docker_install.sh
fi

# Use systemd for managing Docker
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
BTC_VERSION="0.20.0"
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
LND_VERSION="v0.10.3-beta"
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

# Upgrade Loop
echo "Upgrading loopd..."
LOOP_VERSION="v0.6.4-beta"
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
LNDHUB_VERSION="v1.2.0"
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


# Install Caravan
CARAVAN_VERSION="v0.3.2"
CARAVAN_UPGRADE_URL=https://github.com/unchained-capital/caravan/archive/${CARAVAN_VERSION}.tar.gz
CARAVAN_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.caravan_url
CARAVAN_SETTINGS_UPDATE_FILE=/home/bitcoin/.mynode/.caravan_settings_1
CURRENT=""
if [ -f $CARAVAN_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $CARAVAN_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$CARAVAN_UPGRADE_URL" ] || [ ! -f $CARAVAN_SETTINGS_UPDATE_FILE ]; then
    cd /opt/mynode
    rm -rf caravan

    rm -f caravan.tar.gz
    wget $CARAVAN_UPGRADE_URL -O caravan.tar.gz
    tar -xzf caravan.tar.gz 
    rm -f caravan.tar.gz
    mv caravan-* caravan
    chown -R bitcoin:bitcoin caravan

    cd caravan
    sudo -u bitcoin npm install --only=production
    echo $CARAVAN_UPGRADE_URL > $CARAVAN_UPGRADE_URL_FILE
    touch $CARAVAN_SETTINGS_UPDATE_FILE
fi
cd ~


# Install cors proxy (my fork)
CORSPROXY_UPGRADE_URL=https://github.com/tehelsper/CORS-Proxy/archive/v1.7.0.tar.gz
CORSPROXY_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.corsproxy_url
CURRENT=""
if [ -f $CORSPROXY_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $CORSPROXY_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$CORSPROXY_UPGRADE_URL" ]; then
    cd /opt/mynode
    rm -rf corsproxy

    rm -f corsproxy.tar.gz
    wget $CORSPROXY_UPGRADE_URL -O corsproxy.tar.gz
    tar -xzf corsproxy.tar.gz 
    rm -f corsproxy.tar.gz
    mv CORS-* corsproxy

    cd corsproxy
    npm install
    echo $CORSPROXY_UPGRADE_URL > $CORSPROXY_UPGRADE_URL_FILE
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

# Upgrade JoinMarket
echo "Upgrading JoinMarket..."
if [ $IS_RASPI = 1 ] || [ $IS_X86 = 1 ]; then
    JOINMARKET_VERSION=v0.6.2
    JOINMARKET_UPGRADE_URL=https://github.com/JoinMarket-Org/joinmarket-clientserver/archive/$JOINMARKET_VERSION.tar.gz
    JOINMARKET_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.joinmarket_version
    CURRENT=""
    if [ -f $JOINMARKET_UPGRADE_URL_FILE ]; then
        CURRENT=$(cat $JOINMARKET_UPGRADE_URL_FILE)
    fi
    if [ "$CURRENT" != "$JOINMARKET_VERSION" ]; then
        # Download and build JoinMarket
        cd /opt/mynode

        # Backup old version in case config / wallet was stored within folder
        if [ ! -d /opt/mynode/jm_backup ] && [ -d /opt/mynode/joinmarket-clientserver ]; then
            cp -R /opt/mynode/joinmarket-clientserver /opt/mynode/jm_backup
            chown -R bitcoin:bitcoin /opt/mynode/jm_backup
        fi

        rm -rf joinmarket-clientserver

        sudo -u bitcoin wget $JOINMARKET_UPGRADE_URL -O joinmarket.tar.gz
        sudo -u bitcoin tar -xvf joinmarket.tar.gz
        sudo -u bitcoin rm joinmarket.tar.gz
        mv joinmarket-clientserver-* joinmarket-clientserver
        
        cd joinmarket-clientserver
        yes | ./install.sh --without-qt

        echo $JOINMARKET_VERSION > $JOINMARKET_UPGRADE_URL_FILE
    fi
fi

# Install Whirlpool
WHIRLPOOL_UPGRADE_URL=https://github.com/Samourai-Wallet/whirlpool-client-cli/releases/download/0.10.5/whirlpool-client-cli-0.10.5-run.jar
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
RTL_VERSION="v0.8.3"
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

# Upgrade BTC RPC Explorer
BTCRPCEXPLORER_UPGRADE_URL=https://github.com/janoside/btc-rpc-explorer/archive/v2.0.2.tar.gz
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


# Upgrade LNBits
LNBITS_UPGRADE_URL=https://github.com/lnbits/lnbits/archive/raspiblitz.tar.gz
LNBITS_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.lnbits_url
CURRENT=""
if [ -f $LNBITS_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $LNBITS_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$LNBITS_UPGRADE_URL" ]; then
    cd /opt/mynode
    rm -rf lnbits
    sudo -u bitcoin wget $LNBITS_UPGRADE_URL -O lnbits.tar.gz
    sudo -u bitcoin tar -xvf lnbits.tar.gz
    sudo -u bitcoin rm lnbits.tar.gz
    sudo -u bitcoin mv lnbits-* lnbits
    cd lnbits

    # Copy over config file
    cp /usr/share/mynode/lnbits.env /opt/mynode/lnbits/.env
    chown bitcoin:bitcoin /opt/mynode/lnbits/.env

    # Install with python 3.7 (Only use "pipenv install --python 3.7" once or it will rebuild the venv!)
    sudo -u bitcoin pipenv --python 3.7 install
    sudo -u bitcoin pipenv run pip install python-dotenv
    sudo -u bitcoin pipenv run pip install -r requirements.txt
    #sudo -u bitcoin pipenv run pip install lnd-grpc # Using REST now (this install takes a LONG time)
    sudo -u bitcoin pipenv run flask migrate || true

    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $LNBITS_UPGRADE_URL > $LNBITS_UPGRADE_URL_FILE
fi


# Upgrade Specter Desktop
SPECTER_UPGRADE_VERSION=0.5.5
if [ $IS_ROCK64 = 1 ] || [ $IS_ROCKPRO64 = 1 ]; then
    SPECTER_UPGRADE_VERSION=0.5.2
fi
SPECTER_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.spectre_url
CURRENT=""
if [ -f $SPECTER_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $SPECTER_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$SPECTER_UPGRADE_VERSION" ]; then
    cd /opt/mynode
    rm -rf specter
    mkdir -p specter
    chown -R bitcoin:bitcoin specter
    cd specter

    # Make venv
    if [ ! -d env ]; then
        sudo -u bitcoin python3 -m venv env
    fi
    source env/bin/activate
    pip3 install ecdsa===0.13.3
    pip3 install cryptoadvance.specter===$SPECTER_UPGRADE_VERSION --upgrade
    deactivate

    echo $SPECTER_UPGRADE_VERSION > $SPECTER_UPGRADE_URL_FILE
fi


# Upgrade Thunderhub
THUNDERHUB_UPGRADE_URL=https://github.com/apotdevin/thunderhub/archive/v0.8.13.tar.gz
THUNDERHUB_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.thunderhub_url
CURRENT=""
if [ -f $THUNDERHUB_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $THUNDERHUB_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$THUNDERHUB_UPGRADE_URL" ]; then
    cd /opt/mynode
    rm -rf thunderhub
    sudo -u bitcoin wget $THUNDERHUB_UPGRADE_URL -O thunderhub.tar.gz
    sudo -u bitcoin tar -xvf thunderhub.tar.gz
    sudo -u bitcoin rm thunderhub.tar.gz
    sudo -u bitcoin mv thunderhub-* thunderhub
    cd thunderhub

    sudo -u bitcoin npm install # --only=production # (can't build with only production)
    sudo -u bitcoin npm run build
    sudo -u bitcoin npx next telemetry disable

    # Setup symlink to service files
    rm -f /opt/mynode/thunderhub/.env.local
    sudo ln -s /mnt/hdd/mynode/thunderhub/.env.local /opt/mynode/thunderhub/.env.local

    echo $THUNDERHUB_UPGRADE_URL > $THUNDERHUB_UPGRADE_URL_FILE
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
TOR_VERSION=$(tor --version)
if [[ "$TOR_VERSION" != *"Tor version 0.4"* ]]; then
    $TORIFY apt-get remove -y tor
    $TORIFY apt-get install -y tor
fi


# Enable fan control
if [ $IS_ROCKPRO64 = 1 ]; then
    systemctl enable fan_control
fi


# Cleanup MOTD
rm -f /etc/update-motd.d/10-armbian-header || true
rm -f /etc/update-motd.d/30-armbian-sysinfo || true
rm -f /etc/update-motd.d/35-armbian-tips || true
rm -f /etc/update-motd.d/40-armbian-updates || true
rm -f /etc/update-motd.d/41-armbian-config || true
rm -f /etc/update-motd.d/98-armbian-autoreboot-warn || true


# Clean apt-cache
apt-get clean

# Enable any new/required services
systemctl enable check_in
systemctl enable docker
systemctl enable bitcoind
systemctl enable lnd
systemctl enable firewall
systemctl enable invalid_block_check
systemctl enable usb_driver_check
systemctl enable https
systemctl enable docker_images
systemctl enable glances
systemctl enable webssh2
systemctl enable tor
systemctl enable loopd
systemctl enable rotate_logs
systemctl enable corsproxy_btcrpc

# Disable any old services
systemctl disable hitch || true
systemctl disable mongodb || true
systemctl disable lnd_admin || true
systemctl disable dhcpcd || true

# Reload service settings
systemctl daemon-reload

# Sync FS
sync
