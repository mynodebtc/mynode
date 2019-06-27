###
### Setup myNode on Rock64
### Run with "sudo"
###

set -x
set -e

if [ "$#" != "1" ]; then
    echo "Usage: $0 <ip address>"
    exit 1
fi
SERVER_IP=$1

# Update OS
apt-get update
apt-get -y upgrade

# Install other tools (run section multiple times to make sure success)
apt-get -y install htop git curl bash-completion jq dphys-swapfile lsof libzmq3-dev
apt-get -y install build-essential python-dev python-pip python3-dev python3-pip 
apt-get -y install transmission-cli fail2ban ufw tclsh bluez python-bluez redis-server
apt-get -y install mongodb-server clang hitch zlib1g-dev libffi-dev file toilet ncdu
apt-get -y install toilet-fonts avahi-daemon figlet libsecp256k1-dev 
apt-get -y install inotify-tools libssl-dev 


# Install other things without recommendation
apt-get -y install --no-install-recommends expect

# Add bitcoin users
getent passwd bitcoin > /dev/null 2&>1
if [ $? -ne 0 ]; then
    useradd -m -s /bin/bash bitcoin
else
    echo "User 'bitcoin' already exists"
fi

# Install python tools (run twice, some broken deps may cause install failures on first try for line 3)
pip install setuptools
pip install wheel
pip install speedtest-cli transmissionrpc flask python-bitcoinrpc redis prometheus_client requests
pip install python-pam python-bitcoinlib psutil
pip install grpcio grpcio-tools googleapis-common-protos 


# Update python3 to 3.7.2
PYTHON3_VERSION=$(python3 --version)
if [ "$PYTHON3_VERSION" != "Python 3.7.2" ]; then
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


# Install Rust
wget https://sh.rustup.rs -O /tmp/setup_rust.sh
/bin/bash /tmp/setup_rust.sh -y

# Install node
curl -sL https://deb.nodesource.com/setup_11.x | bash -
apt-get install -y nodejs

# Install node packages
npm install -g pug-cli browserify uglify-js babel-cli

# Remove existing MOTD login info
rm -rf /etc/motd
rm -rf /etc/update-motd.d/*


#########################################################


# Install Bitcoin
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
    rm -rf /tmp/download
    mkdir -p /tmp/download
    cd /tmp/download

    wget $BTC_UPGRADE_URL -O bitcoin.tar.gz
    tar -xvf bitcoin.tar.gz
    mv bitcoin-* bitcoin
    install -m 0755 -o root -g root -t /usr/local/bin bitcoin/bin/*

    sudo -u bitcoin ln -s /mnt/hdd/mynode/bitcoin /home/bitcoin/.bitcoin
    sudo -u bitcoin ln -s /mnt/hdd/mynode/lnd /home/bitcoin/.lnd
    mkdir /home/admin/.bitcoin
    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $BTC_UPGRADE_URL | sudo tee $BTC_UPGRADE_URL_FILE
fi
cd ~

# Install Lightning
LND_UPGRADE_URL=https://github.com/lightningnetwork/lnd/releases/download/v0.6.1-beta/lnd-linux-armv7-v0.6.1-beta.tar.gz
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
    ln -s /bin/ip /usr/bin/ip

    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $LND_UPGRADE_URL | sudo tee $LND_UPGRADE_URL_FILE
fi
cd ~

# Setup "install" location for some apps
mkdir -p /opt/mynode
chown -R bitcoin:bitcoin /opt/mynode


# Install LND Hub
cd /opt/mynode
rm -rf LndHub
sudo -u bitcoin git clone https://github.com/BlueWallet/LndHub.git
cd LndHub
sudo -u bitcoin npm install
sudo -u bitcoin ln -s /home/bitcoin/.lnd/tls.cert tls.cert
sudo -u bitcoin ln -s /home/bitcoin/.lnd/data/chain/bitcoin/mainnet/admin.macaroon admin.macaroon


# Install electrs (only build to save new version, now included in overlay)
#cd /home/admin/download
#wget https://github.com/romanz/electrs/archive/v0.7.0.tar.gz
#tar -xvf v0.7.0.tar.gz 
#cd electrs-0.7.0
#cargo build --release
#sudo install -g root -o root target/release/electrs /usr/bin/electrs
#cd ~


# Install RTL
cd /opt/mynode
rm -rf RTL
sudo -u bitcoin wget https://github.com/ShahanaFarooqui/RTL/archive/v0.3.3.tar.gz -O RTL.tar.gz
sudo -u bitcoin tar -xvf RTL.tar.gz
sudo -u bitcoin rm RTL.tar.gz
sudo -u bitcoin mv RTL-* RTL
cd RTL
sudo -u bitcoin npm install


# Install LND Admin
cd /opt/mynode
rm -rf lnd-admin
sudo -u bitcoin wget https://github.com/janoside/lnd-admin/archive/v0.10.12.tar.gz -O lnd-admin.tar.gz
sudo -u bitcoin tar -xvf lnd-admin.tar.gz
sudo -u bitcoin rm lnd-admin.tar.gz
sudo -u bitcoin mv lnd-* lnd-admin
cd lnd-admin
sudo -u bitcoin npm install


# Install Bitcoin RPC Explorer
cd /opt/mynode
rm -rf btc-rpc-explorer
sudo -u bitcoin wget https://github.com/janoside/btc-rpc-explorer/archive/v1.0.3.tar.gz -O btc-rpc-explorer.tar.gz
sudo -u bitcoin tar -xvf btc-rpc-explorer.tar.gz
sudo -u bitcoin rm btc-rpc-explorer.tar.gz
sudo -u bitcoin mv btc-rpc-* btc-rpc-explorer
cd btc-rpc-explorer
sudo -u bitcoin npm install


# Install LND Connect
rm -rf /tmp/download
mkdir -p /tmp/download
cd /tmp/download
wget https://github.com/LN-Zap/lndconnect/releases/download/v0.1.0/lndconnect-linux-armv7-v0.1.0.tar.gz -O lndconnect.tar.gz
tar -xvf lndconnect.tar.gz
rm lndconnect.tar.gz
mv lndconnect-* lndconnect
install -m 0755 -o root -g root -t /usr/local/bin lndconnect/* 

#########################################################


# Copy myNode rootfs
rm -rf /tmp/rootfs.tar.gz
rm -rf /tmp/upgrade/

wget http://${SERVER_IP}:8000/mynode_rootfs_rock64.tar.gz -O /tmp/rootfs.tar.gz

tar -xvf /tmp/rootfs.tar.gz -C /tmp/upgrade/

# Install files
cp -rf /tmp/upgrade/out/rootfs_*/* /
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


# Delete junk
rm -rf /home/admin/download
rm -rf /home/admin/.bash_history
rm -rf /home/bitcoin/.bash_history
rm -rf /root/.bash_history
rm -rf /root/.ssh/known_hosts
rm -rf /etc/resolv.conf
rm -rf /tmp/*

sync

### MAKE IMAGE NOW ###
# This prevents auto gen files like certs to be part of the base image
# Must make sure image can boot after this point and fully come up


