#!/bin/bash

###
### Setup myNode (all devices)
### Run with "sudo"
###

set -x
set -e

if [ "$#" != "1" ]; then
    echo "Usage: $0 <ip address>"
    exit 1
fi
SERVER_IP=$1

# Determine Device
IS_ARMBIAN=0
IS_ROCK64=0
IS_ROCKPRO64=0
IS_RASPI=0
IS_RASPI3=0
IS_RASPI4=0
IS_X86=0
IS_UNKNOWN=0
DEVICE_TYPE="unknown"
MODEL=$(cat /proc/device-tree/model) || IS_UNKNOWN=1
uname -a | grep amd64 && IS_X86=1 || true
if [[ $MODEL == *"Rock64"* ]]; then
    IS_ARMBIAN=1
    IS_ROCK64=1
elif [[ $MODEL == *"RockPro64"* ]]; then
    IS_ARMBIAN=1
    IS_ROCKPRO64=1
elif [[ $MODEL == *"Raspberry Pi 3"* ]]; then
    IS_RASPI=1
    IS_RASPI3=1
elif [[ $MODEL == *"Raspberry Pi 4"* ]]; then
    IS_RASPI=1
    IS_RASPI4=1
fi

if [ $IS_UNKNOWN = 1 ]; then
    echo "UNKNOWN DEVICE TYPE"
    exit 1
fi

# Set kernel settings
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

# Set DNS for install
echo "" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo "nameserver 9.9.9.9" >> /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf


# Make sure FS is expanded for armbian
if [ $IS_ARMBIAN = 1 ] ; then
    /usr/lib/armbian/armbian-resize-filesystem start
fi


# Download rootfs
rm -rf /tmp/rootfs.tar.gz
rm -rf /tmp/upgrade/
mkdir -p /tmp/upgrade

TARBALL=""
if [ $IS_ROCK64 = 1 ]; then
    TARBALL="mynode_rootfs_rock64.tar.gz"
elif [ $IS_ROCKPRO64 = 1 ]; then
    TARBALL="mynode_rootfs_rockpro64.tar.gz"
elif [ $IS_RASPI3 = 1 ]; then
    TARBALL="mynode_rootfs_raspi3.tar.gz"
elif [ $IS_RASPI4 = 1 ]; then
    TARBALL="mynode_rootfs_raspi4.tar.gz"
elif [ $IS_X86 = 1 ]; then
    TARBALL="mynode_rootfs_debian.tar.gz"
fi
wget http://${SERVER_IP}:8000/${TARBALL} -O /tmp/rootfs.tar.gz


# Create any necessary users


# Update sources
apt-get -y update

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
curl https://keybase.io/roasbeef/pgp_keys.asc | gpg --import
curl https://raw.githubusercontent.com/JoinMarket-Org/joinmarket-clientserver/master/pubkeys/AdamGibson.asc | gpg --import
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964
curl https://keybase.io/suheb/pgp_keys.asc | gpg --import
gpg  --keyserver hkps://keyserver.ubuntu.com --recv-keys DE23E73BFA8A0AD5587D2FCDE80D2F3F311FD87E #loopd
curl https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --import  # tor
gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -                                       # tor


# Update OS
apt -y update # Needed to accept new repos
apt-get -y update
apt-get -y upgrade

# Install other tools (run section multiple times to make sure success)
export DEBIAN_FRONTEND=noninteractive
apt-get -y install apt-transport-https
apt-get -y install htop git curl bash-completion jq dphys-swapfile lsof libzmq3-dev
apt-get -y install build-essential python-dev python-pip python3-dev python3-pip 
apt-get -y install transmission-cli fail2ban ufw tclsh bluez python-bluez redis-server
#apt-get -y install mongodb-org
apt-get -y install clang hitch zlib1g-dev libffi-dev file toilet ncdu
apt-get -y install toilet-fonts avahi-daemon figlet libsecp256k1-dev 
apt-get -y install inotify-tools libssl-dev tor tmux screen fonts-dejavu
apt-get -y install python-grpcio python3-grpcio
apt-get -y install pv sysstat network-manager rsync parted unzip pkg-config
apt-get -y install libfreetype6-dev libpng-dev libatlas-base-dev libgmp-dev libltdl-dev 
apt-get -y install libffi-dev libssl-dev glances python3-bottle automake libtool libltdl7
apt -y -qq install apt-transport-https ca-certificates
apt-get -y install xorg chromium openbox lightdm openjdk-11-jre libevent-dev ncurses-dev
apt-get -y install zlib1g-dev libudev-dev libusb-1.0-0-dev python3-venv gunicorn
apt-get -y install libsqlite3-dev torsocks python3-requests


# Make sure some software is removed
apt-get -y purge ntp # (conflicts with systemd-timedatectl)
apt-get -y purge chrony # (conflicts with systemd-timedatectl)


# Install other things without recommendation
apt-get -y install --no-install-recommends expect


# Install nginx
mkdir -p /var/log/nginx
$TORIFY apt-get -y install nginx || true
# Install may fail, so we need to edit the default config file and reconfigure
rm -f /etc/nginx/modules-enabled/50-mod-* || true
echo "" > /etc/nginx/sites-available/default
dpkg --configure -a


# Add bitcoin users
useradd -m -s /bin/bash bitcoin || true
usermod -a -G debian-tor bitcoin


# Install pip packages
pip2 install setuptools
pip2 install --upgrade setuptools
pip2 install wheel
pip2 install --upgrade wheel
pip2 install speedtest-cli transmissionrpc flask python-bitcoinrpc redis prometheus_client requests
pip2 install python-pam python-bitcoinlib psutil
pip2 install grpcio grpcio-tools googleapis-common-protos 
pip2 install tzupdate virtualenv pysocks


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


# Install Python3 specific tools (run multiple times to make sure success)
pip3 install wheel setuptools
pip3 install bitstring lnd-grpc pycoin aiohttp connectrum python-bitcoinlib
pip3 install gnureadline
pip3 install lndmanage==0.10.0   # Install LND Manage (keep up to date with LND)
pip3 install docker-compose
pip3 install pipenv
pip3 install pysocks


# Install Rust
if [ ! -f /tmp/installed_rust ]; then
    wget https://sh.rustup.rs -O /tmp/setup_rust.sh
    /bin/bash /tmp/setup_rust.sh -y
    touch /tmp/installed_rust
fi

# Install node
if [ ! -f /tmp/installed_node ]; then
    curl -sL https://deb.nodesource.com/setup_11.x | bash -
    apt-get install -y nodejs
    touch /tmp/installed_node
fi

# Install docker
curl -sSL https://get.docker.com | sed 's/sleep 20/sleep 1/' | sudo sh || true

# Use systemd for managing docker
rm -f /etc/init.d/docker
rm -f /etc/systemd/system/multi-user.target.wants/docker.service
systemctl -f enable docker.service

groupadd docker || true
usermod -aG docker admin
usermod -aG docker bitcoin
usermod -aG docker root

# Install node packages
npm install -g pug-cli browserify uglify-js babel-cli

# Remove existing MOTD login info
rm -rf /etc/motd
rm -rf /etc/update-motd.d/*


#########################################################


# Install Bitcoin
BTC_VERSION="0.20.1"
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
    gpg --verify SHA256SUMS.asc

    # Install Bitcoin
    tar -xvf bitcoin-$BTC_VERSION-$ARCH.tar.gz
    mv bitcoin-$BTC_VERSION bitcoin
    install -m 0755 -o root -g root -t /usr/local/bin bitcoin/bin/*
    if [ ! -L /home/bitcoin/.bitcoin ]; then
        sudo -u bitcoin ln -s /mnt/hdd/mynode/bitcoin /home/bitcoin/.bitcoin
    fi
    if [ ! -L /home/bitcoin/.lnd ]; then
        sudo -u bitcoin ln -s /mnt/hdd/mynode/lnd /home/bitcoin/.lnd
    fi
    mkdir -p /home/admin/.bitcoin
    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $BTC_UPGRADE_URL > $BTC_UPGRADE_URL_FILE
fi
cd ~

# Install Lightning
LND_VERSION="v0.11.0-beta"
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
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download

    wget $LND_UPGRADE_URL
    wget $LND_UPGRADE_MANIFEST_URL
    wget $LND_UPGRADE_MANIFEST_SIG_URL

    gpg --verify manifest-*.txt.sig

    tar -xzf lnd-*.tar.gz
    mv $LND_ARCH-$LND_VERSION lnd
    install -m 0755 -o root -g root -t /usr/local/bin lnd/*
    ln -s /bin/ip /usr/bin/ip || true

    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $LND_UPGRADE_URL > $LND_UPGRADE_URL_FILE
fi
cd ~

# Install Loopd
echo "Installing loopd..."
LOOP_VERSION="v0.8.0-beta"
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


# Setup "install" location for some apps
mkdir -p /opt/mynode
chown -R bitcoin:bitcoin /opt/mynode


# Install LND Hub
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
CARAVAN_VERSION="v0.2.0"
CARAVAN_UPGRADE_URL=https://github.com/unchained-capital/caravan/archive/${CARAVAN_VERSION}.tar.gz
CARAVAN_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.caravan_url
CURRENT=""
if [ -f $CARAVAN_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $CARAVAN_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$CARAVAN_UPGRADE_URL" ]; then
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
fi
cd ~


# Install cors proxy (my fork)
CORSPROXY_UPGRADE_URL=https://github.com/tehelsper/CORS-Proxy/archive/v1.7.0.tar.gz
CORSPROXY_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.corsproxy_url
CURRENT=""
if [ -f $CORSPROXY_UPGRADE_URL ]; then
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


# Install Electrs (only build to save new version, now included in overlay)
#cd /home/admin/download
#wget https://github.com/romanz/electrs/archive/v0.7.0.tar.gz
#tar -xvf v0.7.0.tar.gz 
#cd electrs-0.7.0
#cargo build --release
#sudo install -g root -o root target/release/electrs /usr/bin/electrs
#cd ~


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

# Install JoinMarket
echo "Install JoinMarket..."
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


# Install RTL
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

    sudo -u bitcoin tar -xvf RTL.tar.gz
    sudo -u bitcoin rm RTL.tar.gz
    sudo -u bitcoin mv RTL-* RTL
    cd RTL
    sudo -u bitcoin NG_CLI_ANALYTICS=false npm install --only=production
    
    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $RTL_UPGRADE_URL > $RTL_UPGRADE_URL_FILE
fi


# Install BTC RPC Explorer
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


# Install LNBits
# Find URL by going to https://github.com/lnbits/lnbits/releases and finding the exact commit for the mynode tag
LNBITS_UPGRADE_URL=https://github.com/lnbits/lnbits/archive/dd2a282158d5774c2a3c85c164a10709c13ef7b4.tar.gz
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
    #cp /usr/share/mynode/lnbits.env /opt/mynode/lnbits/.env
    #chown bitcoin:bitcoin /opt/mynode/lnbits/.env

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
SPECTER_UPGRADE_VERSION=0.6.0
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
THUNDERHUB_UPGRADE_URL=https://github.com/apotdevin/thunderhub/archive/v0.9.0.tar.gz
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
    NGROK_URL=https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-arm.zip
    if [ $IS_X86 = 1 ]; then
        NGROK_URL=https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-386.zip
    fi
    wget $NGROK_URL
    unzip ngrok-*.zip
    cp ngrok /usr/bin/
fi

# Make sure we are using legacy iptables
update-alternatives --set iptables /usr/sbin/iptables-legacy || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true


#########################################################


# Copy myNode rootfs (downloaded earlier)
tar -xvf /tmp/rootfs.tar.gz -C /tmp/upgrade/

# Install files
if [ $IS_X86 = 1 ]; then
    rsync -r -K /tmp/upgrade/out/rootfs_*/* /
else
    cp -rf /tmp/upgrade/out/rootfs_*/* /
fi
sleep 1
sync
sleep 1


# Enable fan control
if [ $IS_ROCKPRO64 = 1 ]; then
    systemctl enable fan_control
fi


# Setup myNode Startup Script
systemctl daemon-reload
systemctl enable check_in
systemctl enable docker
systemctl enable mynode
systemctl enable quicksync
systemctl enable torrent_check
systemctl enable firewall
systemctl enable bandwidth
systemctl enable www
systemctl enable drive_check
systemctl enable bitcoind
systemctl enable lnd
systemctl enable loopd
systemctl enable lnd_unlock
systemctl enable lnd_backup
systemctl enable lnd_admin_files
systemctl enable lndconnect
systemctl enable redis-server
#systemctl enable mongodb
#systemctl enable electrs # DISABLED BY DEFAULT
#systemctl enable lndhub # DISABLED BY DEFAULT
#systemctl enable btc_rpc_explorer # DISABLED BY DEFAULT
systemctl enable tls_proxy
systemctl enable rtl
systemctl enable tor
systemctl enable invalid_block_check
systemctl enable usb_driver_check
systemctl enable docker_images
systemctl enable glances
#systemctl enable netdata # DISABLED BY DEFAULT
systemctl enable webssh2
systemctl enable rotate_logs
systemctl enable corsproxy_btcrpc


# Regenerate MAC Address for Armbian devices
if [ $IS_ARMBIAN = 1 ]; then
    . /usr/lib/armbian/armbian-common
    CONNECTION="$(nmcli -f UUID,ACTIVE,DEVICE,TYPE connection show --active | grep ethernet | tail -n1)"
    UUID=$(awk -F" " '/ethernet/ {print $1}' <<< "${CONNECTION}")
    get_random_mac
    nmcli connection modify $UUID ethernet.cloned-mac-address $MACADDR
    nmcli connection modify $UUID -ethernet.mac-address ""
fi


# Disable services
systemctl disable hitch || true
systemctl disable mongodb || true
systemctl disable dhcpcd || true


# Delete junk
rm -rf /home/admin/download
rm -rf /home/admin/.bash_history
rm -rf /home/bitcoin/.bash_history
rm -rf /root/.bash_history
rm -rf /root/.ssh/known_hosts
rm -rf /etc/resolv.conf
rm -rf /tmp/*
rm -rf ~/setup_device.sh
rm -rf /etc/motd # Remove simple motd for update-motd.d

# Reset MAC address for Armbian devices
if [ $IS_ARMBIAN = 1 ] ; then
    . /usr/lib/armbian/armbian-common
    CONNECTION="$(nmcli -f UUID,ACTIVE,DEVICE,TYPE connection show --active | tail -n1)"
    UUID=$(awk -F" " '/ethernet/ {print $1}' <<< "${CONNECTION}")
    get_random_mac
    nmcli connection modify $UUID ethernet.cloned-mac-address $MACADDR
    nmcli connection modify $UUID -ethernet.mac-address ""
fi

sync

set +x
echo ""
echo ""
echo "##################################"
echo "          SETUP COMPLETE          "
echo "   Reboot your device to begin!   "
echo "##################################"
echo ""
echo ""

### MAKE IMAGE NOW ###
# This prevents auto gen files like certs to be part of the base image
# Must make sure image can boot after this point and fully come up


