#!/bin/bash


### Clear existing rootfs ###
rm -rf out/rootfs*
mkdir -p out/rootfs_rock64/
mkdir -p out/rootfs_raspi/
#mkdir -p out/rootfs_free/


### Make standard rootfs ###
# Copy Base
cp -rf rootfs/standard/* out/rootfs_rock64/


#### Make mini rootfs ###
# Copy base
cp -rf rootfs/standard/* out/rootfs_raspi/
cp -rf rootfs/raspi/* out/rootfs_raspi/

# Remove unnecessary files
#rm -rf out/rootfs_raspi/etc/systemd/system/electrs.service
#rm -rf out/rootfs_raspi/var/www/mynode/static/electrum_server.html
#rm -rf out/rootfs_raspi/var/www/mynode/static/bitcoind_address.html
#rm -rf out/rootfs_raspi/var/www/mynode/static/bitcoind_block.html
#rm -rf out/rootfs_raspi/var/www/mynode/static/bitcoind_explorer.html
#rm -rf out/rootfs_raspi/var/www/mynode/static/bitcoind_tx.html
#rm -rf out/rootfs_raspi/var/www/mynode/electrum_server.py

#### Make free rootfs ###
#cp -rf rootfs/free/* out/rootfs_free/