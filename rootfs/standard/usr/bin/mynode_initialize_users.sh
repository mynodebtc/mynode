#!/bin/bash

# Create any necessary users
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

# User updates and settings
grep "joinmarket" /etc/sudoers || (echo 'joinmarket ALL=(ALL) NOPASSWD:ALL' | EDITOR='tee -a' visudo)
passwd -l root
