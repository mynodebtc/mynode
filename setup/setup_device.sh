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
IS_RASPI4_ARM64=0
IS_X86=0
IS_64_BIT=0
IS_UNKNOWN=0
DEVICE_TYPE="unknown"
MODEL=$(cat /proc/device-tree/model) || IS_UNKNOWN=1
uname -a | grep amd64 && IS_X86=1 && IS_UNKNOWN=0 || true
if [[ $MODEL == *"Rock64"* ]]; then
    IS_ARMBIAN=1
    IS_ROCK64=1
    IS_64_BIT=1
elif [[ $MODEL == *"RockPro64"* ]]; then
    IS_ARMBIAN=1
    IS_ROCKPRO64=1
    IS_64_BIT=1
elif [[ $MODEL == *"Raspberry Pi 3"* ]]; then
    IS_RASPI=1
    IS_RASPI3=1
elif [[ $MODEL == *"Raspberry Pi 4"* ]]; then
    IS_RASPI=1
    IS_RASPI4=1
    UNAME=$(uname -a)
    if [[ $UNAME == *"aarch64"* ]]; then
        IS_RASPI4_ARM64=1
        IS_64_BIT=1
    fi
fi

if [ $IS_UNKNOWN = 1 ]; then
    echo "UNKNOWN DEVICE TYPE"
    exit 1
fi

# Set kernel settings
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

# Set DNS for install (old)
#echo "" > /etc/resolv.conf
#echo "nameserver 1.1.1.1" >> /etc/resolv.conf
#echo "nameserver 9.9.9.9" >> /etc/resolv.conf
#echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Set DNS for install (new)
echo "" >> /etc/dhcp/dhclient.conf
echo "append domain-name-servers 1.1.1.1, 208.67.222.222, 8.8.8.8;" >> /etc/dhcp/dhclient.conf
dhclient -r

# Test DNS resolution issues (may have only seen issues on bad device)
#ping -c 2 raspberrypi.org
#ping -c 2 raspbian.raspberrypi.org
#ping -c 2 pythonhosted.org
#ping -c 2 python.org
#ping -c 2 piwheels.org


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

# Extract rootfs (so we can reference temporary files)
tar -xvf /tmp/rootfs.tar.gz -C /tmp/upgrade/
TMP_INSTALL_PATH="/tmp/upgrade/out/rootfs_*"

# Source file containing app versions
source /tmp/upgrade/out/rootfs_*/usr/share/mynode/mynode_app_versions.sh


# Create any necessary users
useradd -m -s /bin/bash bitcoin || true
useradd -m -s /bin/bash joinmarket || true

# Setup bitcoin user folders
mkdir -p /home/bitcoin/.mynode/
chown bitcoin:bitcoin /home/bitcoin
chown -R bitcoin:bitcoin /home/bitcoin/.mynode/

# Update sources
apt-get -y update --allow-releaseinfo-change

# Add sources
apt-get -y install apt-transport-https curl gnupg
DEBIAN_VERSION=$(lsb_release -c | awk '{ print $2 }')
# Tor (arm32 support was dropped)
if [ $IS_64_BIT = 1 ]; then
    grep -qxF "deb https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
    grep -qxF "deb-src https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb-src https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
fi
# Raspbian mirrors
# if [ $IS_RASPI = 1 ]; then
#     grep -qxF "deb http://plug-mirror.rcac.purdue.edu/raspbian/ ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb http://plug-mirror.rcac.purdue.edu/raspbian/ ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
#     grep -qxF "deb http://mirrors.ocf.berkeley.edu/raspbian/raspbian ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb http://mirrors.ocf.berkeley.edu/raspbian/raspbian ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
# fi

# Import Keys
curl https://keybase.io/roasbeef/pgp_keys.asc | gpg --import
curl https://keybase.io/bitconner/pgp_keys.asc | gpg --import
curl https://keybase.io/guggero/pgp_keys.asc | gpg --import # Pool
curl https://raw.githubusercontent.com/JoinMarket-Org/joinmarket-clientserver/master/pubkeys/AdamGibson.asc | gpg --import
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys E777299FC265DD04793070EB944D35F9AC3DB76A # Bitcoin - Michael Ford (fanquake)
curl https://keybase.io/suheb/pgp_keys.asc | gpg --import
curl https://samouraiwallet.com/pgp.txt | gpg --import # two keys from Samourai team
gpg  --keyserver hkp://keyserver.ubuntu.com --recv-keys DE23E73BFA8A0AD5587D2FCDE80D2F3F311FD87E #loopd
curl https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --import  # tor
gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -                                       # tor


# Update OS
apt -y update # Needed to accept new repos
apt-get -y update

# Freeze any packages we don't want to update
if [ $IS_X86 = 1 ]; then
    apt-mark hold grub*
fi
apt-mark hold redis-server

# Upgrade packages
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
apt-get -y install sqlite3 libsqlite3-dev torsocks python3-requests libsystemd-dev
apt-get -y install libjpeg-dev zlib1g-dev psmisc hexyl libbz2-dev liblzma-dev netcat-openbsd
apt-get -y install hdparm iotop

# Install device specific packages
if [ $IS_X86 = 1 ]; then
    apt-get -y install cloud-init
fi

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


# Update users
usermod -a -G debian-tor bitcoin

# Make admin a member of bitcoin
adduser admin bitcoin

# Install pip packages
pip2 install setuptools
pip2 install --upgrade setuptools
pip2 install wheel
pip2 install --upgrade wheel
pip2 install speedtest-cli transmissionrpc flask python-bitcoinrpc redis prometheus_client requests
pip2 install python-pam python-bitcoinlib psutil
pip2 install grpcio grpcio-tools googleapis-common-protos
pip2 install tzupdate virtualenv pysocks redis qrcode image subprocess32


# Install Rust (only needed on 32-bit RPi for building some python wheels)
if [ ! -f $HOME/.cargo/env ]; then
    wget https://sh.rustup.rs -O /tmp/setup_rust.sh
    /bin/bash /tmp/setup_rust.sh -y --default-toolchain none
    sync
fi
if [ -f $HOME/.cargo/env ]; then
    # Remove old toolchains
    source $HOME/.cargo/env
    TOOLCHAINS=$(rustup toolchain list)
    for toolchain in $TOOLCHAINS; do
        if [[ "$toolchain" == *"linux"* ]] && [[ "$toolchain" != *"${RUST_VERSION}"* ]]; then
            rustup toolchain remove $toolchain || true
        fi
    done
    # Manage rust toolchains
    if [ $IS_RASPI = 1 ] && [ $IS_RASPI4_ARM64 = 0 ]; then
        # Install and use desired version
        rustup install $RUST_VERSION
        rustup default $RUST_VERSION
        rustc --version
    fi
fi


# Install Python3 (latest)
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
pip3 install --upgrade pip wheel setuptools
pip3 install lnd-grpc gnureadline docker-compose pipenv bcrypt pysocks redis --no-cache-dir
pip3 install flask pam python-bitcoinrpc prometheus_client psutil transmissionrpc qrcode image --no-cache-dir


# Install node
if [ ! -f /tmp/installed_node ]; then
    curl -sL https://deb.nodesource.com/setup_$NODE_JS_VERSION | bash -
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
npm install -g npm@$NODE_NPM_VERSION

# Remove existing MOTD login info
rm -rf /etc/motd
rm -rf /etc/update-motd.d/*

# Install LNDManage
# - skip, not default app


#########################################################


# Install Bitcoin
ARCH="UNKNOWN"
if [ $IS_RASPI = 1 ]; then
    ARCH="arm-linux-gnueabihf"
    if [ $IS_RASPI4_ARM64 = 1 ]; then
        ARCH="aarch64-linux-gnu"
    fi
elif [ $IS_ROCK64 = 1 ] || [ $IS_ROCKPRO64 = 1 ]; then
    ARCH="aarch64-linux-gnu"
elif [ $IS_X86 = 1 ]; then
    ARCH="x86_64-linux-gnu"
else
    echo "Unknown Bitcoin Version"
    exit 1
fi
BTC_UPGRADE_URL=https://bitcoincore.org/bin/bitcoin-core-$BTC_VERSION/bitcoin-$BTC_VERSION-$ARCH.tar.gz
BTC_UPGRADE_SHA256SUM_URL=https://bitcoincore.org/bin/bitcoin-core-$BTC_VERSION/SHA256SUMS
BTC_UPGRADE_SHA256SUM_ASC_URL=https://bitcoincore.org/bin/bitcoin-core-$BTC_VERSION/SHA256SUMS.asc
CURRENT=""
if [ -f $BTC_VERSION_FILE ]; then
    CURRENT=$(cat $BTC_VERSION_FILE)
fi
if [ "$CURRENT" != "$BTC_VERSION" ]; then
    # Download and install Bitcoin
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download

    wget $BTC_UPGRADE_URL
    wget $BTC_UPGRADE_SHA256SUM_URL -O SHA256SUMS
    wget $BTC_UPGRADE_SHA256SUM_ASC_URL -O SHA256SUMS.asc

    sha256sum --ignore-missing --check SHA256SUMS
    gpg --verify SHA256SUMS.asc SHA256SUMS |& grep "gpg: Good signature"

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
    echo $BTC_VERSION > $BTC_VERSION_FILE
fi
cd ~

# Install Lightning
LND_ARCH="lnd-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LND_ARCH="lnd-linux-amd64"
fi
if [ $IS_RASPI4_ARM64 = 1 ]; then
    LND_ARCH="lnd-linux-arm64"
fi
LND_UPGRADE_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/$LND_ARCH-$LND_VERSION.tar.gz
CURRENT=""
if [ -f $LND_VERSION_FILE ]; then
    CURRENT=$(cat $LND_VERSION_FILE)
fi
if [ "$CURRENT" != "$LND_VERSION" ]; then
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download

    wget $LND_UPGRADE_URL
    wget $LND_UPGRADE_MANIFEST_URL -O manifest.txt
    wget $LND_UPGRADE_MANIFEST_SIG_URL -O manifest.txt.sig

    gpg --verify manifest.txt.sig manifest.txt

    tar -xzf lnd-*.tar.gz
    mv $LND_ARCH-$LND_VERSION lnd
    install -m 0755 -o root -g root -t /usr/local/bin lnd/*
    ln -s /bin/ip /usr/bin/ip || true

    echo $LND_VERSION > $LND_VERSION_FILE
fi
cd ~

# Install Loop
echo "Installing loop..."
LOOP_ARCH="loop-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LOOP_ARCH="loop-linux-amd64"
fi
if [ $IS_RASPI4_ARM64 = 1 ]; then
    LOOP_ARCH="loop-linux-arm64"
fi
LOOP_UPGRADE_URL=https://github.com/lightninglabs/loop/releases/download/$LOOP_VERSION/$LOOP_ARCH-$LOOP_VERSION.tar.gz
CURRENT=""
if [ -f $LOOP_VERSION_FILE ]; then
    CURRENT=$(cat $LOOP_VERSION_FILE)
fi
if [ "$CURRENT" != "$LOOP_VERSION" ]; then
    # Download and install Loop
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download

    wget $LOOP_UPGRADE_URL
    wget $LOOP_UPGRADE_MANIFEST_URL -O manifest.txt
    wget $LOOP_UPGRADE_MANIFEST_SIG_URL -O manifest.txt.sig

    gpg --verify manifest.txt.sig manifest.txt
    if [ $? == 0 ]; then
        # Install Loop
        tar -xzf loop-*.tar.gz
        mv $LOOP_ARCH-$LOOP_VERSION loop
        install -m 0755 -o root -g root -t /usr/local/bin loop/*

        # Mark current version
        echo $LOOP_VERSION > $LOOP_VERSION_FILE
    else
        echo "ERROR UPGRADING LND - GPG FAILED"
    fi
fi

# Install Pool
echo "Installing pool..."
POOL_ARCH="pool-linux-armv7"
if [ $IS_X86 = 1 ]; then
    POOL_ARCH="pool-linux-amd64"
fi
if [ $IS_RASPI4_ARM64 = 1 ]; then
    POOL_ARCH="pool-linux-arm64"
fi
POOL_UPGRADE_URL=https://github.com/lightninglabs/pool/releases/download/$POOL_VERSION/$POOL_ARCH-$POOL_VERSION.tar.gz
CURRENT=""
if [ -f $POOL_VERSION_FILE ]; then
    CURRENT=$(cat $POOL_VERSION_FILE)
fi
if [ "$CURRENT" != "$POOL_VERSION" ]; then
    # Download and install pool
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download

    wget $POOL_UPGRADE_URL
    wget $POOL_UPGRADE_MANIFEST_URL -O manifest.txt
    wget $POOL_UPGRADE_MANIFEST_SIG_URL -O manifest.txt.sig

    gpg --verify manifest.txt.sig manifest.txt
    if [ $? == 0 ]; then
        # Install Pool
        tar -xzf pool-*.tar.gz
        mv $POOL_ARCH-$POOL_VERSION pool
        install -m 0755 -o root -g root -t /usr/local/bin pool/*

        # Mark current version
        echo $POOL_VERSION > $POOL_VERSION_FILE
    else
        echo "ERROR UPGRADING POOL - GPG FAILED"
    fi
fi

# Install Lightning Terminal
echo "Installing lit..."
LIT_ARCH="lightning-terminal-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LIT_ARCH="lightning-terminal-linux-amd64"
fi
if [ $IS_RASPI4_ARM64 = 1 ]; then
    LIT_ARCH="lightning-terminal-linux-arm64"
fi
LIT_UPGRADE_URL=https://github.com/lightninglabs/lightning-terminal/releases/download/$LIT_VERSION/$LIT_ARCH-$LIT_VERSION.tar.gz
CURRENT=""
if [ -f $LIT_VERSION_FILE ]; then
    CURRENT=$(cat $LIT_VERSION_FILE)
fi
if [ "$CURRENT" != "$LIT_VERSION" ]; then
    # Download and install lit
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download

    wget $LIT_UPGRADE_URL
    wget $LIT_UPGRADE_MANIFEST_URL -O manifest.txt
    wget $LIT_UPGRADE_MANIFEST_SIG_URL  -O manifest.txt.sig

    gpg --verify manifest.txt.sig manifest.txt
    if [ $? == 0 ]; then
        # Install lit
        tar -xzf lightning-terminal-*.tar.gz
        mv $LIT_ARCH-$LIT_VERSION lightning-terminal
        install -m 0755 -o root -g root -t /usr/local/bin lightning-terminal/lit*

        # Mark current version
        echo $LIT_VERSION > $LIT_VERSION_FILE
    else
        echo "ERROR UPGRADING LIT - GPG FAILED"
    fi
fi
cd ~


# Setup "install" location for some apps
mkdir -p /opt/mynode
chown -R bitcoin:bitcoin /opt/mynode


# Install LND Hub
LNDHUB_UPGRADE_URL=https://github.com/BlueWallet/LndHub/archive/$LNDHUB_VERSION.tar.gz
CURRENT=""
if [ -f $LNDHUB_VERSION_FILE ]; then
    CURRENT=$(cat $LNDHUB_VERSION_FILE)
fi
if [ "$CURRENT" != "$LNDHUB_VERSION" ]; then
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
    echo $LNDHUB_VERSION > $LNDHUB_VERSION_FILE
fi
cd ~

# Install Caravan
# Skip - no longer default app


# Install cors proxy (my fork)
CORSPROXY_UPGRADE_URL=https://github.com/tehelsper/CORS-Proxy/archive/$CORSPROXY_VERSION.tar.gz
CURRENT=""
if [ -f $CORSPROXY_VERSION_FILE ]; then
    CURRENT=$(cat $CORSPROXY_VERSION_FILE)
fi
if [ "$CURRENT" != "$CORSPROXY_VERSION" ]; then
    cd /opt/mynode
    rm -rf corsproxy

    rm -f corsproxy.tar.gz
    wget $CORSPROXY_UPGRADE_URL -O corsproxy.tar.gz
    tar -xzf corsproxy.tar.gz
    rm -f corsproxy.tar.gz
    mv CORS-* corsproxy

    cd corsproxy
    npm install
    echo $CORSPROXY_VERSION > $CORSPROXY_VERSION_FILE
fi
cd ~


# Install Electrs (just mark version, now included in overlay)
echo $ELECTRS_VERSION > $ELECTRS_VERSION_FILE


# Install recent version of secp256k1
echo "Installing secp256k1..."
SECP256K1_UPGRADE_URL=https://github.com/bitcoin-core/secp256k1/archive/$SECP256K1_VERSION.tar.gz
CURRENT=""
if [ -f $SECP256K1_VERSION_FILE ]; then
    CURRENT=$(cat $SECP256K1_VERSION_FILE)
fi
if [ "$CURRENT" != "$SECP256K1_VERSION" ]; then
    rm -rf /tmp/secp256k1
    cd /tmp/
    git clone https://github.com/bitcoin-core/secp256k1.git
    cd secp256k1

    ./autogen.sh
    ./configure --enable-module-recovery --disable-jni --enable-experimental --enable-module-ecdh --enable-benchmark=no
    make
    make install
    cp -f include/* /usr/include/

    echo $SECP256K1_VERSION > $SECP256K1_VERSION_FILE
fi

echo "Installing JoinInBox..."
if [ $IS_RASPI = 1 ] || [ $IS_X86 = 1 ]; then
    JOININBOX_UPGRADE_URL=https://github.com/openoms/joininbox/archive/$JOININBOX_VERSION.tar.gz
    CURRENT=""
    if [ -f $JOININBOX_VERSION_FILE ]; then
        CURRENT=$(cat $JOININBOX_VERSION_FILE)
    fi
    if [ "$CURRENT" != "$JOININBOX_VERSION" ]; then
        # Download and build JoinInBox
        cd /home/joinmarket
        
        # Delete all non-hidden files
        rm -rf *
        rm -rf joininbox-*

        sudo -u joinmarket wget $JOININBOX_UPGRADE_URL -O joininbox.tar.gz
        sudo -u joinmarket tar -xvf joininbox.tar.gz
        sudo -u joinmarket rm joininbox.tar.gz
        mv joininbox-* joininbox

        chmod -R +x ./joininbox/
        sudo -u joinmarket cp -rf ./joininbox/scripts/* .

        echo $JOININBOX_VERSION > $JOININBOX_VERSION_FILE
    fi
fi

# Install Whirlpool
WHIRLPOOL_UPGRADE_URL=https://code.samourai.io/whirlpool/whirlpool-client-cli/uploads/$WHIRLPOOL_UPLOAD_FILE_ID/whirlpool-client-cli-$WHIRLPOOL_VERSION-run.jar
WHIRLPOOL_SIG_URL=https://code.samourai.io/whirlpool/whirlpool-client-cli/uploads/$WHIRLPOOL_UPLOAD_SIG_ID/whirlpool-client-cli-$WHIRLPOOL_VERSION-run.jar.sig.asc
CURRENT=""
if [ -f $WHIRLPOOL_VERSION_FILE ]; then
    CURRENT=$(cat $WHIRLPOOL_VERSION_FILE)
fi
if [ "$CURRENT" != "$WHIRLPOOL_VERSION" ]; then
    sudo -u bitcoin mkdir -p /opt/mynode/whirlpool
    cd /opt/mynode/whirlpool
    sudo rm -rf *.jar
    sudo -u bitcoin wget -O whirlpool.jar $WHIRLPOOL_UPGRADE_URL

    #wget -O whirlpool.asc $WHIRLPOOL_SIG_URL
    cp -f $TMP_INSTALL_PATH/usr/share/whirlpool/whirlpool.asc whirlpool.asc
    gpg --verify whirlpool.asc

    echo $WHIRLPOOL_VERSION > $WHIRLPOOL_VERSION_FILE
fi


# Install RTL
RTL_UPGRADE_URL=https://github.com/Ride-The-Lightning/RTL/archive/$RTL_VERSION.tar.gz
RTL_UPGRADE_ASC_URL=https://github.com/Ride-The-Lightning/RTL/releases/download/$RTL_VERSION/$RTL_VERSION.tar.gz.asc
CURRENT=""
if [ -f $RTL_VERSION_FILE ]; then
    CURRENT=$(cat $RTL_VERSION_FILE)
fi
if [ "$CURRENT" != "$RTL_VERSION" ]; then
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

    echo $RTL_VERSION > $RTL_VERSION_FILE
fi


# Install BTC RPC Explorer
BTCRPCEXPLORER_UPGRADE_URL=https://github.com/janoside/btc-rpc-explorer/archive/$BTCRPCEXPLORER_VERSION.tar.gz
CURRENT=""
if [ -f $BTCRPCEXPLORER_VERSION_FILE ]; then
    CURRENT=$(cat $BTCRPCEXPLORER_VERSION_FILE)
fi
if [ "$CURRENT" != "$BTCRPCEXPLORER_VERSION" ]; then
    cd /opt/mynode
    rm -rf btc-rpc-explorer
    sudo -u bitcoin wget $BTCRPCEXPLORER_UPGRADE_URL -O btc-rpc-explorer.tar.gz
    sudo -u bitcoin tar -xvf btc-rpc-explorer.tar.gz
    sudo -u bitcoin rm btc-rpc-explorer.tar.gz
    sudo -u bitcoin mv btc-rpc-* btc-rpc-explorer
    cd btc-rpc-explorer
    sudo -u bitcoin npm install --only=production

    echo $BTCRPCEXPLORER_VERSION > $BTCRPCEXPLORER_VERSION_FILE
fi


# Install LNBits
# Find URL by going to https://github.com/lnbits/lnbits/releases and finding the exact commit for the mynode tag
LNBITS_UPGRADE_URL=https://github.com/lnbits/lnbits/archive/$LNBITS_VERSION.tar.gz
CURRENT=""
if [ -f $LNBITS_VERSION_FILE ]; then
    CURRENT=$(cat $LNBITS_VERSION_FILE)
fi
if [ "$CURRENT" != "$LNBITS_VERSION" ]; then
    cd /opt/mynode
    rm -rf lnbits
    sudo -u bitcoin wget $LNBITS_UPGRADE_URL -O lnbits.tar.gz
    sudo -u bitcoin tar -xvf lnbits.tar.gz
    sudo -u bitcoin rm lnbits.tar.gz
    sudo -u bitcoin mv lnbits-* lnbits
    cd lnbits

    # Copy over config file
    cp $TMP_INSTALL_PATH/usr/share/mynode/lnbits.env /opt/mynode/lnbits/.env
    chown bitcoin:bitcoin /opt/mynode/lnbits/.env

    # Install lnbits
    sudo -u bitcoin python3 -m venv lnbits_venv
    sudo -u bitcoin ./lnbits_venv/bin/pip install -r requirements.txt
    sudo -u bitcoin ./lnbits_venv/bin/quart assets
    #sudo -u bitcoin ./lnbits_venv/bin/quart migrate # Can't migrate since we don't have HDD in setup

    echo $LNBITS_VERSION > $LNBITS_VERSION_FILE
fi


# Upgrade Specter Desktop
CURRENT=""
if [ -f $SPECTER_VERSION_FILE ]; then
    CURRENT=$(cat $SPECTER_VERSION_FILE)
fi
if [ "$CURRENT" != "$SPECTER_VERSION" ]; then
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
    pip3 install cryptoadvance.specter===$SPECTER_VERSION --upgrade
    deactivate

    echo $SPECTER_VERSION > $SPECTER_VERSION_FILE
fi


# Upgrade Thunderhub
THUNDERHUB_UPGRADE_URL=https://github.com/apotdevin/thunderhub/archive/$THUNDERHUB_VERSION.tar.gz
CURRENT=""
if [ -f $THUNDERHUB_VERSION_FILE ]; then
    CURRENT=$(cat $THUNDERHUB_VERSION_FILE)
fi
if [ "$CURRENT" != "$THUNDERHUB_VERSION" ]; then
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

    echo $THUNDERHUB_VERSION > $THUNDERHUB_VERSION_FILE
fi


# Install LND Connect
LNDCONNECTARCH="lndconnect-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LNDCONNECTARCH="lndconnect-linux-amd64"
fi
LNDCONNECT_UPGRADE_URL=https://github.com/LN-Zap/lndconnect/releases/download/v0.2.0/$LNDCONNECTARCH-$LNDCONNECT_VERSION.tar.gz
CURRENT=""
if [ -f $LNDCONNECT_VERSION_FILE ]; then
    CURRENT=$(cat $LNDCONNECT_VERSION_FILE)
fi
if [ "$CURRENT" != "$LNDCONNECT_VERSION" ]; then
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download
    wget $LNDCONNECT_UPGRADE_URL -O lndconnect.tar.gz
    tar -xvf lndconnect.tar.gz
    rm lndconnect.tar.gz
    mv lndconnect-* lndconnect
    install -m 0755 -o root -g root -t /usr/local/bin lndconnect/*

    echo $LNDCONNECT_VERSION > $LNDCONNECT_VERSION_FILE
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


# Upgrade CKbunker
CKBUNKER_UPGRADE_URL=https://github.com/Coldcard/ckbunker/archive/$CKBUNKER_VERSION.tar.gz
CURRENT=""
if [ -f $CKBUNKER_VERSION_FILE ]; then
    CURRENT=$(cat $CKBUNKER_VERSION_FILE)
fi
if [ "$CURRENT" != "$CKBUNKER_VERSION" ]; then
    cd /opt/mynode
    sudo -u bitcoin wget $CKBUNKER_UPGRADE_URL -O ckbunker.tar.gz
    sudo -u bitcoin tar -xvf ckbunker.tar.gz
    sudo -u bitcoin rm ckbunker.tar.gz
    sudo -u bitcoin mv ckbunker-* ckbunker
    cd ckbunker

    # Make venv
    if [ ! -d env ]; then
        sudo -u bitcoin python3 -m venv env
    fi
    source env/bin/activate
    pip3 install -r requirements.txt
    pip3 install --editable .
    deactivate

    echo $CKBUNKER_VERSION > $CKBUNKER_VERSION_FILE
fi


# Upgrade Sphinx Relay
SPHINXRELAY_UPGRADE_URL=https://github.com/stakwork/sphinx-relay/archive/$SPHINXRELAY_VERSION.tar.gz
CURRENT=""
if [ -f $SPHINXRELAY_VERSION_FILE ]; then
    CURRENT=$(cat $SPHINXRELAY_VERSION_FILE)
fi
if [ "$CURRENT" != "$SPHINXRELAY_VERSION" ]; then
    cd /opt/mynode
    rm -rf sphinxrelay
    sudo -u bitcoin wget $SPHINXRELAY_UPGRADE_URL -O sphinx-relay.tar.gz
    sudo -u bitcoin tar -xvf sphinx-relay.tar.gz
    sudo -u bitcoin rm sphinx-relay.tar.gz
    sudo -u bitcoin mv sphinx-relay-* sphinxrelay
    cd sphinxrelay

    sudo -u bitcoin npm install

    echo $SPHINXRELAY_VERSION > $SPHINXRELAY_VERSION_FILE
fi

# Mark docker images for install (on SD so install occurs after drive attach)
touch /home/bitcoin/.mynode/install_mempool
touch /home/bitcoin/.mynode/install_dojo

# SKIPPING BOS - OPTIONAL APP
# SKIPPING PYBLOCK - OPTIONAL APP
# SKIPPING WARDEN - OPTIONAL APP


# Make sure we are using legacy iptables
update-alternatives --set iptables /usr/sbin/iptables-legacy || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true


#########################################################


# Install files (downloaded and extracted earlier)
if [ $IS_X86 = 1 ] || [ $IS_RASPI4_ARM64 = 1 ]; then
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

# Random Cleanup
rm -rf /opt/download
mkdir -p /opt/download

# Clean apt-cache
apt-get clean

# Setup myNode Startup Script
systemctl daemon-reload
systemctl enable check_in
systemctl enable background
systemctl enable docker
systemctl enable mynode
systemctl enable quicksync
systemctl enable torrent_check
systemctl enable firewall
systemctl enable bandwidth
systemctl enable www
systemctl enable drive_check
systemctl enable bitcoin
systemctl enable seed_bitcoin_peers
systemctl enable lnd
systemctl enable loop
systemctl enable pool
systemctl enable lit
#systemctl enable lnd_unlock # NOT NECESSARY WITH LND 0.13+
systemctl enable lnd_backup
systemctl enable lnd_admin_files
systemctl enable lndconnect
systemctl enable redis-server
#systemctl enable mongodb
#systemctl enable electrs # DISABLED BY DEFAULT
#systemctl enable lndhub # DISABLED BY DEFAULT
#systemctl enable btcrpcexplorer # DISABLED BY DEFAULT
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
