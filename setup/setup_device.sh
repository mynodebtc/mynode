#!/bin/bash

###
### Setup myNode (all devices)
### Run with "sudo"
###

set -x
set -e

if [ "$#" != "1" ]; then
    echo "Usage: $0 <ip address | online>"
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
IS_ROCKPI4=0
IS_X86=0
IS_32_BIT=0
IS_64_BIT=0
IS_UNKNOWN=0
DEVICE_TYPE="unknown"
MODEL=$(cat /proc/device-tree/model) || IS_UNKNOWN=1
DEBIAN_VERSION=$(lsb_release -c -s) || DEBIAN_VERSION="unknown"
uname -a | grep amd64 && IS_X86=1 && IS_64_BIT=1 && IS_UNKNOWN=0 || true
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
    IS_32_BIT=1
elif [[ $MODEL == *"Raspberry Pi 4"* ]]; then
    IS_RASPI=1
    IS_RASPI4=1
    IS_32_BIT=1
    UNAME=$(uname -a)
    if [[ $UNAME == *"aarch64"* ]]; then
        IS_RASPI4_ARM64=1
        IS_32_BIT=0
        IS_64_BIT=1
    fi
elif [[ $MODEL == *"ROCK Pi 4"* ]]; then
    IS_ARMBIAN=1
    IS_ROCKPI4=1
    IS_64_BIT=1
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
elif [ $IS_ROCKPI4 = 1 ]; then
    TARBALL="mynode_rootfs_rockpi4.tar.gz"
elif [ $IS_X86 = 1 ]; then
    TARBALL="mynode_rootfs_debian.tar.gz"
fi
if [ "$SERVER_IP" == "online" ]; then
    TARBALL="${TARBALL/"mynode_rootfs_"/"mynode_release_latest_"}"
    wget https://mynodebtc.com/device/upgrade_images/${TARBALL} -O /tmp/rootfs.tar.gz
else
    wget http://${SERVER_IP}:8000/${TARBALL} -O /tmp/rootfs.tar.gz
fi

# Extract rootfs (so we can reference temporary files)
tar -xvf /tmp/rootfs.tar.gz -C /tmp/upgrade/
TMP_INSTALL_PATH="/tmp/upgrade/out/rootfs_*"

# Setup some dependencies
mkdir -p /usr/share/mynode/
cp -f /tmp/upgrade/out/rootfs_*/usr/share/mynode/mynode_device_info.sh /usr/share/mynode/mynode_device_info.sh
cp -f /tmp/upgrade/out/rootfs_*/usr/share/mynode/mynode_config.sh /usr/share/mynode/mynode_config.sh
cp -f /tmp/upgrade/out/rootfs_*/usr/share/mynode/mynode_functions.sh /usr/share/mynode/mynode_functions.sh
cp -f /tmp/upgrade/out/rootfs_*/usr/bin/mynode-get-device-serial /usr/bin/mynode-get-device-serial

# Source file containing app versions
source /tmp/upgrade/out/rootfs_*/usr/share/mynode/mynode_app_versions.sh

# Update SD card
mkdir -p /etc/torrc.d

# Create any necessary users
useradd -p $(openssl passwd -1 bolt) -m -s /bin/bash admin || true
useradd -m -s /bin/bash bitcoin || true
useradd -m -s /bin/bash joinmarket || true
passwd -l root
adduser admin sudo

# Setup bitcoin user folders
mkdir -p /home/bitcoin/.mynode/
chown bitcoin:bitcoin /home/bitcoin
chown -R bitcoin:bitcoin /home/bitcoin/.mynode/

# Update host info
echo "myNode" > /etc/hostname
sed -i 's/rock64/myNode/g' /etc/hosts
sed -i 's/rockpi4-b/myNode/g' /etc/hosts

# Update sources
apt-get -y update --allow-releaseinfo-change

# Add sources
apt-get -y install apt-transport-https curl gnupg ca-certificates
# Tor (arm32 support was dropped)
if [ $IS_64_BIT = 1 ]; then
    grep -qxF "deb https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
    grep -qxF "deb-src https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb-src https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
fi
if [ "$DEBIAN_VERSION" = "buster" ]; then
    grep -qxF "deb http://deb.debian.org/debian buster-backports main" /etc/apt/sources.list  || echo "deb http://deb.debian.org/debian buster-backports main" >> /etc/apt/sources.list
fi
# Add I2P Repo
/bin/bash $TMP_INSTALL_PATH/usr/share/mynode/scripts/add_i2p_repo.sh

# Import Keys
curl https://keybase.io/roasbeef/pgp_keys.asc | gpg --import
curl https://keybase.io/bitconner/pgp_keys.asc | gpg --import
curl https://keybase.io/guggero/pgp_keys.asc | gpg --import # Pool
curl https://raw.githubusercontent.com/JoinMarket-Org/joinmarket-clientserver/master/pubkeys/AdamGibson.asc | gpg --import
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys E777299FC265DD04793070EB944D35F9AC3DB76A # Bitcoin - Michael Ford (fanquake)
curl https://keybase.io/suheb/pgp_keys.asc | gpg --import
curl https://samouraiwallet.com/pgp.txt | gpg --import # two keys from Samourai team
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys DE23E73BFA8A0AD5587D2FCDE80D2F3F311FD87E #loopd
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 26984CB69EB8C4A26196F7A4D7D916376026F177 # Lightning Terminal
wget -q https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc -O- | apt-key add - # Tor
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 648ACFD622F3D138     # Debian Backports
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 0E98404D386FA1D9     # Debian Backports
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 74A941BA219EC810   # Tor
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 66F6C87B98EBCFE2   # I2P (R4SAS)

# Update OS
apt -y update # Needed to accept new repos
apt-get -y update

# Freeze any packages we don't want to update
if [ $IS_X86 = 1 ]; then
    apt-mark hold grub*
fi
#apt-mark hold redis-server

# Upgrade packages
apt-get -y upgrade

# Install other tools (run section multiple times to make sure success)
export DEBIAN_FRONTEND=noninteractive
apt-get -y install apt-transport-https lsb-release
apt-get -y install htop git curl bash-completion jq dphys-swapfile lsof libzmq3-dev
apt-get -y install build-essential python3-dev python3-pip python3-grpcio
apt-get -y install transmission-cli fail2ban ufw tclsh redis-server
apt-get -y install clang cmake hitch zlib1g-dev libffi-dev file toilet ncdu
apt-get -y install toilet-fonts avahi-daemon figlet libsecp256k1-dev
apt-get -y install inotify-tools libssl-dev tor tmux screen fonts-dejavu
apt-get -y install pv sysstat network-manager rsync parted unzip pkg-config
apt-get -y install libfreetype6-dev libpng-dev libatlas-base-dev libgmp-dev libltdl-dev
apt-get -y install libffi-dev libssl-dev python3-bottle automake libtool libltdl7
apt -y -qq install apt-transport-https ca-certificates
apt-get -y install openjdk-11-jre libevent-dev ncurses-dev
apt-get -y install zlib1g-dev libudev-dev libusb-1.0-0-dev python3-venv gunicorn
apt-get -y install sqlite3 libsqlite3-dev torsocks python3-requests libsystemd-dev
apt-get -y install libjpeg-dev zlib1g-dev psmisc hexyl libbz2-dev liblzma-dev netcat-openbsd
apt-get -y install hdparm iotop nut obfs4proxy libpq-dev socat btrfs-progs i2pd

# Install packages dependent on Debian release
if [ "$DEBIAN_VERSION" == "bullseye" ]; then
    apt-get -y install wireguard
elif [ "$DEBIAN_VERSION" == "buster" ]; then
    $TORIFY apt-get -y -t buster-backports install wireguard
else
    echo "========================================="
    echo "== UNKNOWN DEBIAN VERSION: $DEBIAN_VERSION"
    echo "== SOME APPS MAY NOT WORK PROPERLY"
    echo "========================================="
fi

# Install Openbox GUI
if [ $IS_X86 = 1 ]; then
    apt-get -y install xorg chromium openbox lightdm
fi

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
grep "joinmarket" /etc/sudoers || (echo 'joinmarket ALL=(ALL) NOPASSWD:ALL' | EDITOR='tee -a' visudo)


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


# Install Python3 specific tools
pip3 install --upgrade pip wheel setuptools

pip3 install -r $TMP_INSTALL_PATH/usr/share/mynode/mynode_pip3_requirements.txt --no-cache-dir || \
    pip3 install -r $TMP_INSTALL_PATH/usr/share/mynode/mynode_pip3_requirements.txt --no-cache-dir --use-deprecated=html5lib

# For RP4 32-bit, install specific grpcio version known to build (uses proper glibc for wheel)
if [ $IS_32_BIT = 1 ]; then
    pip3 install grpcio==$PYTHON_ARM32_GRPCIO_VERSION grpcio-tools==$PYTHON_ARM32_GRPCIO_VERSION
fi


# Install node
if [ ! -f /tmp/installed_node ]; then
    curl -sL https://deb.nodesource.com/setup_$NODE_JS_VERSION | bash -
    apt-get install -y nodejs
    touch /tmp/installed_node
fi

# Install docker
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update --allow-releaseinfo-change
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true

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
npm install -g yarn

# Install Log2Ram
if [ $IS_RASPI = 1 ]; then
    cd /tmp
    rm -rf log2ram*
    wget https://github.com/azlux/log2ram/archive/v1.2.2.tar.gz -O log2ram.tar.gz
    tar -xvf log2ram.tar.gz
    mv log2ram-* log2ram
    cd log2ram
    chmod +x install.sh
    service log2ram stop
    ./install.sh
    cd ~
fi

# Remove existing MOTD login info
rm -rf /etc/motd
rm -rf /etc/update-motd.d/*

#########################################################


# Install Bitcoin
ARCH="UNKNOWN"
if [ $IS_RASPI = 1 ]; then
    ARCH="arm-linux-gnueabihf"
    if [ $IS_RASPI4_ARM64 = 1 ]; then
        ARCH="aarch64-linux-gnu"
    fi
elif [ $IS_ROCK64 = 1 ] || [ $IS_ROCKPRO64 = 1 ] || [ $IS_ROCKPI4 = 1 ]; then
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
BTC_CLI_COMPLETION_URL=https://raw.githubusercontent.com/bitcoin/bitcoin/v$BTC_VERSION/contrib/bitcoin-cli.bash-completion
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

    # Install bash-completion for bitcoin-cli
    wget $BTC_CLI_COMPLETION_URL -O bitcoin-cli.bash-completion
    sudo cp bitcoin-cli.bash-completion /etc/bash_completion.d/bitcoin-cli
fi
cd ~

# Install Lightning
LND_ARCH="lnd-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LND_ARCH="lnd-linux-amd64"
fi
if [ $IS_RASPI4_ARM64 = 1 ] || [ $IS_ROCK64 = 1 ] || [ $IS_ROCKPRO64 = 1 ] || [ $IS_ROCKPI4 = 1 ]; then
    LND_ARCH="lnd-linux-arm64"
fi
LND_UPGRADE_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/$LND_ARCH-$LND_VERSION.tar.gz
LNCLI_COMPLETION_URL=https://raw.githubusercontent.com/lightningnetwork/lnd/$LND_VERSION/contrib/lncli.bash-completion

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

    # Download bash-completion file for lncli
    wget $LNCLI_COMPLETION_URL
    sudo cp lncli.bash-completion /etc/bash_completion.d/lncli
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

        # Use Python3.7 on RP4 32-bit
        JM_ENV_VARS=""
        if [ $IS_32_BIT = 1 ]; then
            JM_ENV_VARS="export JM_PYTHON=python3.7; "
        fi

        # Install
        sudo -u joinmarket bash -c "cd /home/joinmarket/; ${JM_ENV_VARS} ./install.joinmarket.sh install" || true

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
    sudo -u bitcoin NG_CLI_ANALYTICS=false npm install --only=production --legacy-peer-deps
    sudo -u bitcoin npm install request --save

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

    # Patch versions
    sed -i 's/\^5.3.5/5.3.3/g' package.json || true     # Fixes segfault with 5.3.5 on x86

    sudo -u bitcoin npm install --legacy-peer-deps # --only=production # (can't build with only production)
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

# Make sure "Remote Access" apps are marked installed
touch /home/bitcoin/.mynode/install_tor
touch /home/bitcoin/.mynode/install_premium_plus
touch /home/bitcoin/.mynode/install_vpn

# Mark docker images for install (on SD so install occurs after drive attach)
touch /home/bitcoin/.mynode/install_mempool
touch /home/bitcoin/.mynode/install_btcpayserver
touch /home/bitcoin/.mynode/install_dojo

# SKIPPING LNBITS - OPTIONAL ALL
# SKIPPING CKBUNKER - OPTIONAL APP
# SKIPPING SPHINX - OPTIONAL APP
# SKIPPING BOS - OPTIONAL APP
# SKIPPING PYBLOCK - OPTIONAL APP
# SKIPPING WARDEN - OPTIONAL APP


# Make sure we are using legacy iptables
update-alternatives --set iptables /usr/sbin/iptables-legacy || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true


#########################################################


# Install files (downloaded and extracted earlier)
rsync -r -K /tmp/upgrade/out/rootfs_*/* /
sync
sleep 1


# Mark dynamic applications as defalt application
# ... (none yet)

# Upgrade Dyanmic Applications (must be done after file installation)
# mynode-manage-apps upgrade # not yet working during setup process


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
systemctl enable premium_plus_connect
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
systemctl enable i2pd
systemctl enable invalid_block_check
systemctl enable usb_driver_check
systemctl enable docker_images
systemctl enable glances
#systemctl enable netdata # DISABLED BY DEFAULT
systemctl enable webssh2
systemctl enable rotate_logs
systemctl enable corsproxy_btcrpc
systemctl enable usb_extras


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

# Remove default debian stuff
deluser mynode || true
rm -rf /home/mynode || true

# Remove default Pi stuff
deluser pi || true
rm -rf /home/pi || true

# Regenerate MAC address for some Armbian devices
if [ $IS_ROCK64 = 1 ] || [ $IS_ROCKPRO64 = 1 ] ; then
    . /usr/lib/armbian/armbian-common
    CONNECTION="$(nmcli -f UUID,ACTIVE,DEVICE,TYPE connection show --active | tail -n1)"
    UUID=$(awk -F" " '/ethernet/ {print $1}' <<< "${CONNECTION}")
    get_random_mac
    nmcli connection modify $UUID ethernet.cloned-mac-address $MACADDR
    nmcli connection modify $UUID -ethernet.mac-address ""
fi

# Add generic boot option if UEFI
if [ -f /boot/efi/EFI/debian/grubx64.efi ]; then
    mkdir -p /boot/efi/EFI/BOOT
    cp -f /boot/efi/EFI/debian/grubx64.efi /boot/efi/EFI/BOOT/bootx64.efi
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
