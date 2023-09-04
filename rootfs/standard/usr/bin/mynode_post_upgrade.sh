#!/bin/bash

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_functions.sh
source /usr/share/mynode/mynode_app_versions.sh

set -x
set -e

# Make sure time is in the log
date

# Mark we are upgrading
echo "upgrading" > $MYNODE_STATUS_FILE

# Shut down main services to save memory and CPU
/usr/bin/mynode_stop_critical_services.sh

# Check if upgrades use tor
TORIFY=""
if [ -f /mnt/hdd/mynode/settings/torify_apt_get ]; then
    TORIFY="torify"
fi

# Delete ramlog to prevent ram issues (remake necessary folders)
rm -rf /var/log/*
mkdir -p /var/log/nginx
if [ $IS_RASPI = 1 ]; then
    log2ram write || true
    log2ram stop || true
fi

# Skip base upgrades if we are doing an app install / uninstall
if ! skip_base_upgrades ; then

    # Update SD card
    mkdir -p /etc/torrc.d

    # Initialize Users
    /usr/bin/mynode_initialize_users.sh

    # Migrate from version file to version+install combo
    /usr/bin/mynode_migrate_version_files.sh

    # PwnKit vulnerability mitigation
    chmod 0755 /usr/bin/pkexec

    # Stop and disable any old services
    systemctl disable https || true
    systemctl stop https || true
    systemctl disable tls_proxy || true
    systemctl stop tls_proxy || true

    # Create dhparam.pem (do before dpkg configure since its needed for nginx)
    /usr/bin/mynode_gen_dhparam.sh


    # Check if any dpkg installs have failed and correct
    dpkg --configure -a


    # Add sources
    apt-get -y install apt-transport-https
    DEBIAN_VERSION=$(lsb_release -c | awk '{ print $2 }')
    # Tor (arm32 support was dropped)
    if [ $IS_64_BIT = 1 ]; then
        grep -qxF "deb https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
        grep -qxF "deb-src https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb-src https://deb.torproject.org/torproject.org ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
    fi
    if [ -f /mnt/hdd/mynode/settings/tor_repo_disabled ]; then
        sed -i '/^deb https:\/\/deb.torproject.org/d' /etc/apt/sources.list
        sed -i '/^deb-src https:\/\/deb.torproject.org/d' /etc/apt/sources.list
    fi
    if [ "$DEBIAN_VERSION" = "buster" ]; then
        grep -qxF "deb http://deb.debian.org/debian buster-backports main" /etc/apt/sources.list  || echo "deb http://deb.debian.org/debian buster-backports main" >> /etc/apt/sources.list
    fi
    # Add I2P Repo
    /bin/bash /usr/share/mynode/scripts/add_i2p_repo.sh

    # Raspbian mirrors
    #if [ $IS_RASPI = 1 ]; then
    #    grep -qxF "deb http://plug-mirror.rcac.purdue.edu/raspbian/ ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb http://plug-mirror.rcac.purdue.edu/raspbian/ ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
    #    grep -qxF "deb http://mirrors.ocf.berkeley.edu/raspbian/raspbian ${DEBIAN_VERSION} main" /etc/apt/sources.list  || echo "deb http://mirrors.ocf.berkeley.edu/raspbian/raspbian ${DEBIAN_VERSION} main" >> /etc/apt/sources.list
    #fi

    # Import Keys
    set +e
    curl https://keybase.io/roasbeef/pgp_keys.asc | gpg --import
    curl https://keybase.io/bitconner/pgp_keys.asc | gpg --import
    curl https://keybase.io/guggero/pgp_keys.asc | gpg --import # Pool
    curl https://raw.githubusercontent.com/JoinMarket-Org/joinmarket-clientserver/master/pubkeys/AdamGibson.asc | gpg --import
    gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964
    gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys E777299FC265DD04793070EB944D35F9AC3DB76A # Bitcoin - Michael Ford (fanquake)
    curl https://keybase.io/suheb/pgp_keys.asc | gpg --import
    curl https://samouraiwallet.com/pgp.txt | gpg --import # two keys from Samourai team
    gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys DE23E73BFA8A0AD5587D2FCDE80D2F3F311FD87E # Loop (abosworth)
    gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 9FC6B0BFD597A94DBF09708280E5375C094198D8 # Loop (bhandras)
    gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 26984CB69EB8C4A26196F7A4D7D916376026F177 # Lightning Terminal
    gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 187F6ADD93AE3B0CF335AA6AB984570980684DCC # Lightning Terminal
    $TORIFY wget -q https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc -O- | apt-key add - # Tor
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 648ACFD622F3D138   # Debian Backports
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0E98404D386FA1D9   # Debian Backports
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 74A941BA219EC810   # Tor
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 66F6C87B98EBCFE2   # I2P (R4SAS)
    set -e


    # Check for updates (might auto-install all updates later)
    export DEBIAN_FRONTEND=noninteractive
    $TORIFY apt-get update --allow-releaseinfo-change

    # Freeze any packages we don't want to update
    if [ $IS_X86 = 1 ]; then
        apt-mark hold grub*
    fi
    #apt-mark hold redis-server

    # Upgrade packages
    $TORIFY apt-get -y upgrade

    # Install any new software
    $TORIFY apt-get -y install apt-transport-https lsb-release gnupg
    $TORIFY apt-get -y install fonts-dejavu
    $TORIFY apt-get -y install pv sysstat network-manager unzip pkg-config libfreetype6-dev libpng-dev
    $TORIFY apt-get -y install libatlas-base-dev libffi-dev libssl-dev python3-bottle
    $TORIFY apt-get -y -qq install apt-transport-https ca-certificates
    $TORIFY apt-get -y install libgmp-dev automake libtool libltdl-dev libltdl7
    $TORIFY apt-get -y install openjdk-11-jre libevent-dev ncurses-dev
    $TORIFY apt-get -y install libudev-dev libusb-1.0-0-dev python3-venv gunicorn sqlite3 libsqlite3-dev
    $TORIFY apt-get -y install torsocks python3-requests libsystemd-dev libjpeg-dev zlib1g-dev psmisc
    $TORIFY apt-get -y install hexyl libbz2-dev liblzma-dev netcat-openbsd hdparm iotop nut obfs4proxy
    $TORIFY apt-get -y install libpq-dev socat btrfs-progs i2pd apparmor pass

    # Install software specific to debian version
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
        $TORIFY apt-get -y install xorg chromium openbox lightdm
    fi

    # Install device specific packages
    if [ $IS_X86 = 1 ]; then
        $TORIFY apt-get -y install cloud-init
        $TORIFY apt-get -y install intel-microcode || true
    fi

    # Use timesyncd for NTP
    apt-get -y purge ntp # (conflicts with systemd-timedatectl)
    apt-get -y purge chrony # (conflicts with systemd-timedatectl)
    if [ $IS_ARMBIAN = 1 ] ; then
        $TORIFY apt-get -y install systemd-timesyncd || true
        timedatectl set-ntp true || true
    fi


    # Install nginx
    mkdir -p /var/log/nginx || true
    $TORIFY apt-get -y install nginx || true
    # Install may fail, so we need to edit the default config file and reconfigure
    rm -f /etc/nginx/modules-enabled/50-mod-* || true
    echo "" > /etc/nginx/sites-available/default
    dpkg --configure -a


    # Install Go
    GO_ARCH="unknown"
    if [ "$DEVICE_ARCH" == "armv7l" ]; then
        GO_ARCH="armv6l"
    elif [ "$DEVICE_ARCH" == "aarch64" ]; then
        GO_ARCH="arm64"
    elif [ "$DEVICE_ARCH" == "x86_64" ]; then
        GO_ARCH="amd64"
    fi
    GO_UPGRADE_URL=https://go.dev/dl/go$GO_VERSION.linux-$GO_ARCH.tar.gz
    CURRENT=""
    if [ -f $GO_VERSION_FILE ]; then
        CURRENT=$(cat $GO_VERSION_FILE)
    fi
    if [ "$CURRENT" != "$GO_VERSION" ]; then
        rm -rf /opt/download
        mkdir -p /opt/download
        cd /opt/download

        wget $GO_UPGRADE_URL -O go.tar.gz
        rm -rf /usr/local/go && tar -C /usr/local -xzf go.tar.gz

        # Mark current version
        echo $GO_VERSION > $GO_VERSION_FILE
    fi
    echo "export GOBIN=/usr/local/go/bin; PATH=\$PATH:/usr/local/go/bin" > /etc/profile.d/go.sh
    grep -qxF '. /etc/profile.d/go.sh' /root/.bashrc || echo '. /etc/profile.d/go.sh' >> /root/.bashrc


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


    # Update Python3
    CURRENT_PYTHON3_VERSION=$(python3 --version)
    if [[ "$CURRENT_PYTHON3_VERSION" != *"Python ${PYTHON_VERSION}"* ]]; then
        mkdir -p /opt/download
        cd /opt/download
        rm -rf Python-*

        wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz -O python.tar.xz
        tar xf python.tar.xz

        # Build and install python
        cd Python-*
        ./configure
        make -j4
        make install

        # Mark apps using python as needing re-install
        rm -f /home/bitcoin/.mynode/specter_version
        rm -f /home/bitcoin/.mynode/pyblock_version
        rm -f /home/bitcoin/.mynode/ckbunker_version
        rm -f /home/bitcoin/.mynode/joininbox_version_latest

        cd ~
    else
        echo "Python up to date"
    fi

    # Add to python path
    [ -d /usr/local/lib/python2.7/dist-packages ] && echo "/var/pynode" > /usr/local/lib/python2.7/dist-packages/pynode.pth
    [ -d /usr/local/lib/python3.7/site-packages ] && echo "/var/pynode" > /usr/local/lib/python3.7/site-packages/pynode.pth
    [ -d /usr/local/lib/python3.8/site-packages ] && echo "/var/pynode" > /usr/local/lib/python3.8/site-packages/pynode.pth

    # Remove old python files so new copies are used (files migrated to pynode)
    set +x
    PYNODE_FILES="/var/pynode/*.py"
    for pynode_file in $PYNODE_FILES; do
        echo "Migrating pynode file $pynode_file..."
        pynode_file="$(basename -- $pynode_file)"
        rm -f /var/www/mynode/${pynode_file}    # .py
        rm -f /var/www/mynode/${pynode_file}c   # .pyc
    done
    set -x


    # Install any pip3 software
    pip3 install --upgrade pip setuptools wheel || pip3 install --upgrade pip setuptools wheel --use-deprecated=html5lib
    
    pip3 install -r /usr/share/mynode/mynode_pip3_requirements.txt --no-cache-dir || \
        pip3 install -r /usr/share/mynode/mynode_pip3_requirements.txt --no-cache-dir --use-deprecated=html5lib

    # For RP4 32-bit, install specific grpcio version known to build (uses proper glibc for wheel)
    if [ $IS_32_BIT = 1 ]; then
        pip3 install grpcio==$PYTHON_ARM32_GRPCIO_VERSION grpcio-tools==$PYTHON_ARM32_GRPCIO_VERSION
    fi

    # Update Node
    if [ -f /etc/apt/sources.list.d/nodesource.list ]; then
        CURRENT_NODE_VERSION=$(cat /etc/apt/sources.list.d/nodesource.list)
        if [[ "$CURRENT_NODE_VERSION" != *"node_${NODE_JS_VERSION}"* ]]; then
            # Upgrade node
            curl -sL https://deb.nodesource.com/setup_${NODE_JS_VERSION} | bash -
            apt-get install -y nodejs

            # Mark apps using node as needing re-install
            rm -f /home/bitcoin/.mynode/lndhub_version
            rm -f /home/bitcoin/.mynode/sphinxrelay_version
            rm -f /home/bitcoin/.mynode/thunderhub_version
            rm -f /home/bitcoin/.mynode/corsproxy_version
            rm -f /home/bitcoin/.mynode/rtl_version
            rm -f /home/bitcoin/.mynode/caravan_version
            rm -f /home/bitcoin/.mynode/btcrpcexplorer_version
            rm -f /home/bitcoin/.mynode/bos_version
        else
            echo "Node version match"
        fi
    else
        echo "No node apt sources file?"
    fi

    # Update NPM (Node Package Manager)
    #npm install -g npm@$NODE_NPM_VERSION
    npm install -g yarn @quasar/cli
    
    # Install Docker
    mkdir -p /etc/apt/keyrings
    $TORIFY curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    $TORIFY apt-get update --allow-releaseinfo-change
    $TORIFY apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
    
    # Use systemd for managing Docker
    rm -f /etc/init.d/docker
    rm -f /etc/systemd/system/multi-user.target.wants/docker.service
    systemctl -f enable docker.service

    groupadd docker || true
    usermod -aG docker admin
    usermod -aG docker bitcoin
    usermod -aG docker root


    # Install node packages

fi

# Install LNDManage
if should_install_app "lndmanage" ; then
    pip3 install lndmanage==$LNDMANAGE_VERSION --no-cache-dir
    echo $LNDMANAGE_VERSION > $LNDMANAGE_VERSION_FILE
fi

# Upgrade BTC
echo "Upgrading BTC..."
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
BTC_CLI_COMPLETION_URL=https://raw.githubusercontent.com/bitcoin/bitcoin/v$BTC_VERSION/contrib/completions/bash/bitcoin-cli.bash-completion
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
    if [ $? == 0 ]; then
        gpg --verify SHA256SUMS.asc SHA256SUMS |& grep "gpg: Good signature"
        if [ $? == 0 ]; then
            # Install Bitcoin
            tar -xvf bitcoin-$BTC_VERSION-$ARCH.tar.gz
            mv bitcoin-$BTC_VERSION bitcoin
            install -m 0755 -o root -g root -t /usr/local/bin bitcoin/bin/*

            # Mark current version
            echo $BTC_VERSION > $BTC_VERSION_FILE

            # Install bash-completion for bitcoin-cli
            wget $BTC_CLI_COMPLETION_URL -O bitcoin-cli.bash-completion
            sudo cp bitcoin-cli.bash-completion /etc/bash_completion.d/bitcoin-cli
        else
            echo "ERROR UPGRADING BITCOIN - GPG FAILED"
        fi
    else
        echo "ERROR UPGRADING BITCOIN - SHASUM FAILED"
    fi
fi

# Upgrade LND
echo "Upgrading LND..."
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
    # Download and install LND
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download

    wget $LND_UPGRADE_URL
    wget $LND_UPGRADE_MANIFEST_URL -O manifest.txt
    wget $LND_UPGRADE_MANIFEST_ROASBEEF_SIG_URL -O manifest_roasbeef.txt.sig || true
    wget $LND_UPGRADE_MANIFEST_GUGGERO_SIG_URL -O manifest_guggero.txt.sig || true

    gpg --verify manifest_roasbeef.txt.sig manifest.txt || \
    gpg --verify manifest_guggero.txt.sig manifest.txt
    if [ $? == 0 ]; then
        # Install LND
        tar -xzf lnd-*.tar.gz
        mv $LND_ARCH-$LND_VERSION lnd
        install -m 0755 -o root -g root -t /usr/local/bin lnd/*

        # Mark current version
        echo $LND_VERSION > $LND_VERSION_FILE
    else
        echo "ERROR UPGRADING LND - GPG FAILED"
    fi

    # Download bash-completion file for lncli
    wget $LNCLI_COMPLETION_URL
    sudo cp lncli.bash-completion /etc/bash_completion.d/lncli
fi

# Upgrade Loop
echo "Upgrading loop..."
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
        echo "ERROR UPGRADING LOOP - GPG FAILED"
    fi
fi

# Upgrade Pool
echo "Upgrading pool..."
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

# Upgrade Lightning Terminal
echo "Upgrading lit..."
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

# Upgrade Lightning Chantools
echo "Upgrading chantools..."
CHANTOOLS_ARCH="chantools-linux-armv7"
if [ $IS_X86 = 1 ]; then
    CHANTOOLS_ARCH="chantools-linux-amd64"
fi
if [ $IS_RASPI4_ARM64 = 1 ]; then
    CHANTOOLS_ARCH="chantools-linux-arm64"
fi
CHANTOOLS_UPGRADE_URL=https://github.com/lightninglabs/chantools/releases/download/$CHANTOOLS_VERSION/$CHANTOOLS_ARCH-$CHANTOOLS_VERSION.tar.gz
CURRENT=""
if [ -f $CHANTOOLS_VERSION_FILE ]; then
    CURRENT=$(cat $CHANTOOLS_VERSION_FILE)
fi
if [ "$CURRENT" != "$CHANTOOLS_VERSION" ]; then
    # Download and install lit
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download

    wget $CHANTOOLS_UPGRADE_URL
    wget $CHANTOOLS_UPGRADE_MANIFEST_URL -O manifest.txt
    wget $CHANTOOLS_UPGRADE_MANIFEST_SIG_URL  -O manifest.txt.sig

    gpg --verify manifest.txt.sig manifest.txt
    if [ $? == 0 ]; then
        # Install lit
        tar -xzf chantools-*.tar.gz
        mv $CHANTOOLS_ARCH-$CHANTOOLS_VERSION chantools
        install -m 0755 -o root -g root -t /usr/local/bin chantools/chantools

        # Mark current version
        echo $CHANTOOLS_VERSION > $CHANTOOLS_VERSION_FILE
    else
        echo "ERROR UPGRADING CHANTOOLS - GPG FAILED"
    fi
fi

# Install LndHub
if should_install_app "lndhub" ; then
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
fi


# Install Caravan
if should_install_app "caravan" ; then
    CARAVAN_UPGRADE_URL=https://github.com/unchained-capital/caravan/archive/caravan-$CARAVAN_VERSION.tar.gz
    CURRENT=""
    if [ -f $CARAVAN_VERSION_FILE ]; then
        CURRENT=$(cat $CARAVAN_VERSION_FILE)
    fi
    if [ "$CURRENT" != "$CARAVAN_VERSION" ] || [ ! -f $CARAVAN_SETTINGS_UPDATE_FILE ]; then
        cd /opt/mynode
        rm -rf caravan

        rm -f caravan.tar.gz
        wget $CARAVAN_UPGRADE_URL -O caravan.tar.gz
        tar -xzf caravan.tar.gz
        rm -f caravan.tar.gz
        mv caravan-* caravan
        chown -R bitcoin:bitcoin caravan

        cd caravan

        # Change path to / from /caravan
        sed -i 's|/caravan/#|/#|' vite.config.js

        sudo -u bitcoin npm install
        sudo -u bitcoin npm run build
        echo $CARAVAN_VERSION > $CARAVAN_VERSION_FILE
        touch $CARAVAN_SETTINGS_UPDATE_FILE
    fi
    cd ~
fi


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


# Upgrade electrs (just mark version, included in overlay)
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

# Upgrade JoininBox
echo "Upgrading JoinInBox..."
if should_install_app "joininbox" ; then
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
            sudo -u joinmarket bash -c "cd /home/joinmarket/; ${JM_ENV_VARS} ./install.joinmarket.sh --install install" || true
            sudo -u joinmarket bash -c "cd /home/joinmarket/; ${JM_ENV_VARS} ./install.joinmarket-api.sh on" || true            
            
            # Enable obwatcher service
            systemctl enable ob-watcher

            echo $JOININBOX_VERSION > $JOININBOX_VERSION_FILE
        fi
    fi
fi

# Install Whirlpool
if should_install_app "whirlpool" ; then
    WHIRLPOOL_UPGRADE_URL=https://code.samourai.io/whirlpool/whirlpool-client-cli/uploads/$WHIRLPOOL_UPLOAD_FILE_ID/whirlpool-client-cli-$WHIRLPOOL_VERSION-run.jar
    CURRENT=""
    if [ -f $WHIRLPOOL_VERSION_FILE ]; then
        CURRENT=$(cat $WHIRLPOOL_VERSION_FILE)
    fi
    if [ "$CURRENT" != "$WHIRLPOOL_VERSION" ]; then
        sudo -u bitcoin mkdir -p /opt/mynode/whirlpool
        cd /opt/mynode/whirlpool
        sudo rm -rf *.jar
        sudo -u bitcoin wget -O whirlpool.jar $WHIRLPOOL_UPGRADE_URL

        cp -f /usr/share/whirlpool/whirlpool.asc whirlpool.asc
        gpg --verify whirlpool.asc

        echo $WHIRLPOOL_VERSION > $WHIRLPOOL_VERSION_FILE
    fi
fi


# Upgrade RTL
if should_install_app "rtl" ; then
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
        #if [ $? == 0 ]; then
        if [ true ]; then
            sudo -u bitcoin tar -xvf RTL.tar.gz
            sudo -u bitcoin rm RTL.tar.gz
            sudo -u bitcoin mv RTL-* RTL
            cd RTL
            sudo -u bitcoin NG_CLI_ANALYTICS=false npm install --only=production --legacy-peer-deps

            echo $RTL_VERSION > $RTL_VERSION_FILE
        else
            echo "ERROR UPGRADING RTL - GPG FAILED"
        fi
    fi
fi

# Upgrade BTC RPC Explorer
if should_install_app "btcrpcexplorer" ; then
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
fi


# Upgrade Specter Desktop
if should_install_app "specter" ; then
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
fi


# Upgrade Thunderhub
if should_install_app "thunderhub" ; then
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
        #sed -i 's/\^5.3.5/5.3.3/g' package.json || true     # Fixes segfault with 5.3.5 on x86

        sudo -u bitcoin npm install # --only=production # (can't build with only production)
        sudo -u bitcoin npm run build
        sudo -u bitcoin npx next telemetry disable

        # Setup symlink to service files
        rm -f /opt/mynode/thunderhub/.env.local
        sudo ln -s /mnt/hdd/mynode/thunderhub/.env.local /opt/mynode/thunderhub/.env.local

        echo $THUNDERHUB_VERSION > $THUNDERHUB_VERSION_FILE
    fi
fi


# Install LND Connect
LNDCONNECTARCH="lndconnect-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LNDCONNECTARCH="lndconnect-linux-amd64"
fi
LNDCONNECT_UPGRADE_URL=https://github.com/LN-Zap/lndconnect/releases/download/$LNDCONNECT_VERSION/$LNDCONNECTARCH-$LNDCONNECT_VERSION.tar.gz
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
    rm -rf /tmp/ngrok*
    NGROK_URL=https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-arm.zip
    if [ $IS_X86 = 1 ]; then
        NGROK_URL=https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-386.zip
    fi
    wget $NGROK_URL
    unzip ngrok-*.zip
    cp ngrok /usr/bin/
fi


# Upgrade CKbunker
if should_install_app "ckbunker" ; then
    CURRENT=""
    if [ -f $CKBUNKER_VERSION_FILE ]; then
        CURRENT=$(cat $CKBUNKER_VERSION_FILE)
    fi
    if [ "$CURRENT" != "$CKBUNKER_VERSION" ]; then
        cd /opt/mynode
        rm -rf ckbunker

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
fi


# Upgrade Sphinx Relay
if should_install_app "sphinxrelay" ; then
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
fi


# Upgrade pyblock
if should_install_app "pyblock" ; then
    PYBLOCK_UPGRADE_URL=https://github.com/curly60e/pyblock/archive/refs/tags/$PYBLOCK_VERSION.tar.gz
    CURRENT=""
    if [ -f $PYBLOCK_VERSION_FILE ]; then
        CURRENT=$(cat $PYBLOCK_VERSION_FILE)
    fi
    if [ "$CURRENT" != "$PYBLOCK_VERSION" ]; then
        cd /opt/mynode
        rm -rf pyblock

        sudo -u bitcoin wget $PYBLOCK_UPGRADE_URL -O pyblock.tar.gz
        sudo -u bitcoin tar -xvf pyblock.tar.gz
        sudo -u bitcoin rm pyblock.tar.gz
        sudo -u bitcoin mv pyblock-* pyblock
        cd pyblock

        # Make venv
        if [ ! -d env ]; then
            sudo -u bitcoin python3 -m venv env
        fi
        source env/bin/activate
        pip3 install requests
        pip3 install -r requirements.txt
        deactivate

        # Copy default settings files
        sudo -u bitcoin mkdir -p config
        cp -f /usr/share/pyblock/* config/
        chown -R bitcoin:bitcoin config

        echo $PYBLOCK_VERSION > $PYBLOCK_VERSION_FILE
    fi
fi


# Upgrade WARden
if should_install_app "wardenterminal" ; then
    WARDENTERMINAL_UPGRADE_URL=https://github.com/pxsocs/warden_terminal/archive/$WARDENTERMINAL_VERSION.tar.gz
    CURRENT=""
    if [ -f $WARDENTERMINAL_VERSION_FILE ]; then
        CURRENT=$(cat $WARDENTERMINAL_VERSION_FILE)
    fi
    if [ "$CURRENT" != "$WARDENTERMINAL_VERSION" ]; then
        cd /opt/mynode
        rm -rf wardenterminal

        sudo -u bitcoin wget $WARDENTERMINAL_UPGRADE_URL -O wardenterminal.tar.gz
        sudo -u bitcoin tar -xvf wardenterminal.tar.gz
        sudo -u bitcoin rm wardenterminal.tar.gz
        sudo -u bitcoin mv warden_terminal-* wardenterminal
        cd wardenterminal

        # Make venv
        if [ ! -d env ]; then
            sudo -u bitcoin python3 -m venv env
        fi
        source env/bin/activate
        pip3 install -r requirements.txt
        deactivate

        echo $WARDENTERMINAL_VERSION > $WARDENTERMINAL_VERSION_FILE
    fi
fi


# Upgrade Balance of Satoshis
if should_install_app "bos" ; then
    CURRENT=""
    if [ -f $BOS_VERSION_FILE ]; then
        CURRENT=$(cat $BOS_VERSION_FILE)
    fi
    if [ "$CURRENT" != "$BOS_VERSION" ]; then
        npm install -g balanceofsatoshis@$BOS_VERSION

        echo $BOS_VERSION > $BOS_VERSION_FILE
    fi
fi

# Install Rathole proxy
RATHOLEARCH="armv7-unknown-linux-musleabihf"
if [ $IS_X86 = 1 ]; then
    RATHOLEARCH="x86_64-unknown-linux-musl"
elif [ "$DEVICE_ARCH" == "aarch64" ]; then
    RATHOLEARCH="aarch64-unknown-linux-musl"
fi
RATHOLE_UPGRADE_URL=https://github.com/rapiz1/rathole/releases/download/$RATHOLE_VERSION/rathole-$RATHOLEARCH.zip
CURRENT=""
if [ -f $RATHOLE_VERSION_FILE ]; then
    CURRENT=$(cat $RATHOLE_VERSION_FILE)
fi
if [ "$CURRENT" != "$RATHOLE_VERSION" ]; then
    rm -rf /opt/download
    mkdir -p /opt/download
    cd /opt/download
    wget $RATHOLE_UPGRADE_URL -O rathole.zip
    unzip rathole.zip
    rm rathole.zip
    install -o root -g root -t /usr/local/bin rathole

    echo $RATHOLE_VERSION > $RATHOLE_VERSION_FILE
fi

# Make sure "Remote Access" apps are marked installed
touch /home/bitcoin/.mynode/install_tor
touch /home/bitcoin/.mynode/install_premium_plus
touch /home/bitcoin/.mynode/install_vpn

# Init dynamic apps, so any new applications are picked up before reboot
mynode-manage-apps init || true

# Upgrade Dyanmic Applications
mynode-manage-apps upgrade || true


# Upgrade Tor
#rm -f /usr/local/bin/tor || true
#TOR_VERSION=$(tor --version)
#if [[ "$TOR_VERSION" != *"Tor version 0.4"* ]]; then
#    $TORIFY apt-get remove -y tor
#    $TORIFY apt-get install -y tor
#fi


# Enable fan control
if [ $IS_ROCKPRO64 = 1 ]; then
    systemctl enable fan_control
fi


# Update nginx conf file
cp -f /usr/share/mynode/nginx.conf /etc/nginx/nginx.conf


# Cleanup MOTD
rm -f /etc/update-motd.d/10-armbian-header || true
rm -f /etc/update-motd.d/30-armbian-sysinfo || true
rm -f /etc/update-motd.d/35-armbian-tips || true
rm -f /etc/update-motd.d/40-armbian-updates || true
rm -f /etc/update-motd.d/41-armbian-config || true
rm -f /etc/update-motd.d/98-armbian-autoreboot-warn || true


# Random Cleanup
if [ -f /etc/apt/sources.list.d/vscode.list ]; then
    sed -i "s/^deb/#deb/g" /etc/apt/sources.list.d/vscode.list
fi
if [ -f /etc/apt/trusted.gpg.d/microsoft.gpg ]; then
    rm /etc/apt/trusted.gpg.d/microsoft.gpg
fi

rm -rf /opt/download
mkdir -p /opt/download

# Clean apt-cache
apt-get clean

# Enable any new/required services
systemctl enable check_in
systemctl enable premium_plus_connect
systemctl enable background
systemctl enable docker
systemctl enable bitcoin
systemctl enable seed_bitcoin_peers
systemctl enable lnd
systemctl enable lndconnect
systemctl enable lit
systemctl enable firewall
systemctl enable invalid_block_check
systemctl enable usb_driver_check
systemctl enable docker_images
systemctl enable glances
systemctl enable webssh2
systemctl enable tor
systemctl enable i2pd
systemctl enable loop
systemctl enable pool
systemctl enable rotate_logs
systemctl enable corsproxy_btcrpc
systemctl enable usb_extras
systemctl enable rathole

# Disable any old services
systemctl disable bitcoind > /dev/null 2>&1 || true
systemctl disable poold > /dev/null 2>&1 || true
systemctl disable loopd > /dev/null 2>&1 || true
systemctl disable btc_rpc_explorer > /dev/null 2>&1 || true
systemctl disable mempoolspace > /dev/null 2>&1 || true
systemctl disable hitch > /dev/null 2>&1 || true
systemctl disable mongodb > /dev/null 2>&1 || true
systemctl disable lnd_admin > /dev/null 2>&1 || true
systemctl disable lnd_unlock > /dev/null 2>&1 || true
systemctl disable dhcpcd > /dev/null 2>&1 || true
rm -f /etc/systemd/system/bitcoind.service
rm -f /etc/systemd/system/btc_rpc_explorer.service
rm -f /etc/systemd/system/mempoolspace.service
rm -f /etc/systemd/system/poold.service
rm -f /etc/systemd/system/loopd.service

# Reload service settings
systemctl daemon-reload

# Sync FS
sync

# Done!
echo "UPGRADE COMPLETE!!!"
date