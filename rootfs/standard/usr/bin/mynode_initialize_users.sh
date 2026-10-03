#!/bin/bash

source /usr/share/mynode/mynode_device_info.sh

# Create any necessary users
useradd -m -s /bin/bash bitcoin || true
useradd -m -s /bin/bash pivpn || true
useradd -m -s /bin/bash joinmarket || true
useradd -m -s /bin/bash mempool || true

# Setup bitcoin user folders
mkdir -p /home/bitcoin/.mynode/
chown -R bitcoin:bitcoin /home/bitcoin/.mynode/

# Add users to groups
bitcoin_users="admin joinmarket mempool"
for bitcoin_user in $bitcoin_users; do
    adduser $bitcoin_user bitcoin
done
docker_users="admin mempool"
for docker_user in $docker_users; do
    adduser $docker_user docker
done
sudo_users="admin"
for sudo_user in $sudo_users; do
    adduser $sudo_user sudo
done
tor_users="admin joinmarket"
for tor_user in $tor_users; do
    adduser $tor_user debian-tor
done

# User updates and settings
if [ "$DEBIAN_VERSION" -lt "12" ]; then
    grep "joinmarket" /etc/sudoers || (echo 'joinmarket ALL=(ALL) NOPASSWD:ALL' | EDITOR='tee -a' visudo)
elif grep -q "^joinmarket ALL=(ALL) NOPASSWD:ALL$" /etc/sudoers; then
    SUDOERS_TMP=$(mktemp)
    sed '/^joinmarket ALL=(ALL) NOPASSWD:ALL$/d' /etc/sudoers > $SUDOERS_TMP
    if visudo -c -f $SUDOERS_TMP; then
        install -m 0440 -o root -g root $SUDOERS_TMP /etc/sudoers
    fi
    rm -f $SUDOERS_TMP
fi
passwd -l root
