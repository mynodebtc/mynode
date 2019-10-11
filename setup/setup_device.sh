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
IS_ROCK64=0
IS_RASPI3=0
IS_RASPI4=0
IS_X86=0
uname -a | grep aarch64 && IS_ROCK64=1 || IS_RASPI3=1
if [ $IS_RASPI3 -eq 1 ]; then
    cat /proc/cpuinfo | grep 03111 && IS_RASPI4=1 && IS_RASPI3=0 || IS_RASPI3=1
fi
uname -a | grep amd64 && IS_X86=1 || true
if [ $IS_X86 -eq 1 ]; then
    IS_ROCK64=0
    IS_RASPI3=0
    IS_RASPI4=0
fi

# Make sure FS is expanded for Rock64
if [ $IS_ROCK64 = 1 ]; then
    /usr/lib/armbian/armbian-resize-filesystem start
fi

# Add sources


# Update OS
apt -y update # Needed to accept new repos
apt-get -y update
apt-get -y upgrade

# Install other tools (run section multiple times to make sure success)
apt-get -y install htop git curl bash-completion jq dphys-swapfile lsof libzmq3-dev
apt-get -y install build-essential python-dev python-pip python3-dev python3-pip 
apt-get -y install transmission-cli fail2ban ufw tclsh bluez python-bluez redis-server
#apt-get -y install mongodb-org
apt-get -y install clang hitch zlib1g-dev libffi-dev file toilet ncdu
apt-get -y install toilet-fonts avahi-daemon figlet libsecp256k1-dev 
apt-get -y install inotify-tools libssl-dev tor tmux screen
apt-get -y install python-grpcio python3-grpcio
apt-get -y install pv sysstat network-manager rsync parted unzip


# Install other things without recommendation
apt-get -y install --no-install-recommends expect

# Add bitcoin users
useradd -m -s /bin/bash bitcoin || true
usermod -a -G debian-tor bitcoin


# Install pip packages
pip install setuptools
pip install --upgrade setuptools
pip install wheel
pip install --upgrade wheel
pip install speedtest-cli transmissionrpc flask python-bitcoinrpc redis prometheus_client requests
pip install python-pam python-bitcoinlib psutil
pip install grpcio grpcio-tools googleapis-common-protos 
pip install tzupdate


# Update python3 to 3.7.X
PYTHON3_VERSION=$(python3 --version)
if [[ "$PYTHON3_VERSION" != *"Python 3.7"* ]]; then
    mkdir -p /tmp/download
    cd /tmp/download
    wget https://www.python.org/ftp/python/3.7.2/Python-3.7.2.tar.xz
    tar xf Python-3.7.2.tar.xz
    cd Python-3.7.2
    ./configure
    make -j4
    sudo make install
    cd ~
else
    echo "Python up to date"
fi


# Install python3 specific tools (run multiple times to make sure success)
pip3 install wheel setuptools
pip3 install bitstring lnd-grpc pycoin aiohttp connectrum python-bitcoinlib
pip3 install python-bitcointx


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

# Install node packages
npm install -g pug-cli browserify uglify-js babel-cli

# Remove existing MOTD login info
rm -rf /etc/motd
rm -rf /etc/update-motd.d/*


#########################################################


# Install Bitcoin
ARCH="arm-linux-gnueabihf"
if [ $IS_ROCK64 = 1 ]; then
    ARCH="aarch64-linux-gnu"
fi
if [ $IS_X86 = 1 ]; then
    ARCH="x86_64-linux-gnu" 
fi
BTC_UPGRADE_URL=https://bitcoin.org/bin/bitcoin-core-0.18.1/bitcoin-0.18.1-$ARCH.tar.gz
BTC_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.btc_url
CURRENT=""
if [ -f $BTC_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $BTC_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$BTC_UPGRADE_URL" ]; then
    rm -rf /tmp/download
    mkdir -p /tmp/download
    cd /tmp/download

    wget $BTC_UPGRADE_URL -O bitcoin.tar.gz
    tar -xvf bitcoin.tar.gz
    mv bitcoin-* bitcoin
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
LNDARCH="lnd-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LNDARCH="lnd-linux-amd64"
fi
LND_UPGRADE_URL=https://github.com/lightningnetwork/lnd/releases/download/v0.7.1-beta/$LNDARCH-v0.7.1-beta.tar.gz
LND_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.lnd_url
CURRENT=""
if [ -f $LND_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $LND_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$LND_UPGRADE_URL" ]; then
    rm -rf /tmp/download
    mkdir -p /tmp/download
    cd /tmp/download

    wget $LND_UPGRADE_URL -O lnd.tar.gz
    tar -xzf lnd.tar.gz
    mv lnd-* lnd
    install -m 0755 -o root -g root -t /usr/local/bin lnd/*
    ln -s /bin/ip /usr/bin/ip || true

    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $LND_UPGRADE_URL > $LND_UPGRADE_URL_FILE
fi
cd ~

# Setup "install" location for some apps
mkdir -p /opt/mynode
chown -R bitcoin:bitcoin /opt/mynode


# Install LND Hub
if [ ! -f /tmp/installed_lndhub ]; then
    cd /opt/mynode
    rm -rf LndHub
    sudo -u bitcoin git clone https://github.com/BlueWallet/LndHub.git
    cd LndHub
    sudo -u bitcoin npm install
    sudo -u bitcoin ln -s /home/bitcoin/.lnd/tls.cert tls.cert
    sudo -u bitcoin ln -s /home/bitcoin/.lnd/data/chain/bitcoin/mainnet/admin.macaroon admin.macaroon
    touch /tmp/installed_lndhub
fi

# Install electrs (only build to save new version, now included in overlay)
#cd /home/admin/download
#wget https://github.com/romanz/electrs/archive/v0.7.0.tar.gz
#tar -xvf v0.7.0.tar.gz 
#cd electrs-0.7.0
#cargo build --release
#sudo install -g root -o root target/release/electrs /usr/bin/electrs
#cd ~


# Install RTL
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


# Install LND Admin
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


# Install Bitcoin RPC Explorer
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


# Install LND Connect
LNDCONNECTARCH="lndconnect-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LNDCONNECTARCH="lndconnect-linux-amd64"
fi
LNDCONNECT_UPGRADE_URL=https://github.com/LN-Zap/lndconnect/releases/download/v0.1.0/$LNDCONNECTARCH-v0.1.0.tar.gz
LNDCONNECT_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.lndconnect_url
CURRENT=""
if [ -f $LNDCONNECT_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $LNDCONNECT_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$LNDCONNECT_UPGRADE_URL" ]; then
    rm -rf /tmp/download
    mkdir -p /tmp/download
    cd /tmp/download
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

#########################################################


# Copy myNode rootfs
rm -rf /tmp/rootfs.tar.gz
rm -rf /tmp/upgrade/
mkdir -p /tmp/upgrade

TARBALL=""
if [ $IS_ROCK64 = 1 ]; then
    TARBALL="mynode_rootfs_rock64.tar.gz"
elif [ $IS_RASPI3 = 1 ]; then
    TARBALL="mynode_rootfs_raspi3.tar.gz"
elif [ $IS_RASPI4 = 1 ]; then
    TARBALL="mynode_rootfs_raspi4.tar.gz"
elif [ $IS_X86 = 1 ]; then
    TARBALL="mynode_rootfs_debian.tar.gz"
fi
wget http://${SERVER_IP}:8000/${TARBALL} -O /tmp/rootfs.tar.gz

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


# Setup myNode Startup Script
systemctl daemon-reload
systemctl enable mynode
systemctl enable quicksync
systemctl enable torrent_check
systemctl enable firewall
systemctl enable bandwidth
systemctl enable www
systemctl enable drive_check
systemctl enable bitcoind
systemctl enable lnd
systemctl enable lnd_unlock
systemctl enable lnd_backup
systemctl enable lnd_admin_files
systemctl enable lndconnect
systemctl enable redis-server
systemctl enable mongodb
#systemctl enable electrs # DISABLED BY DEFAULT
#systemctl enable lndhub # DISABLED BY DEFAULT
#systemctl enable btc_rpc_explorer # DISABLED BY DEFAULT
systemctl enable tls_proxy
systemctl enable rtl
systemctl enable lnd_admin
systemctl enable tor
systemctl enable invalid_block_check


# Regenerate MAC Address for Rock64
if [ $IS_ROCK64 = 1 ]; then
    . /usr/lib/armbian/armbian-common
    CONNECTION="$(nmcli -f UUID,ACTIVE,DEVICE,TYPE connection show --active | tail -n1)"
    UUID=$(awk -F" " '/ethernet/ {print $1}' <<< "${CONNECTION}")
    get_random_mac
    nmcli connection modify $UUID ethernet.cloned-mac-address $MACADDR
    nmcli connection modify $UUID -ethernet.mac-address ""
fi



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


