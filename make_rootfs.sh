#!/bin/bash

### Clear existing rootfs ###
#rm -rf out/rootfs*
mkdir -p out/rootfs_rock64/
mkdir -p out/rootfs_raspi3/
mkdir -p out/rootfs_raspi4/
mkdir -p out/rootfs_debian/


### Make rock64 rootfs ###
rsync -r -u rootfs/standard/* out/rootfs_rock64/
rsync -r -u rootfs/rock64/* out/rootfs_rock64/
rsync -r -u CHANGELOG out/rootfs_rock64/usr/share/mynode/changelog
rm -f out/mynode_rootfs_rock64.tar.gz
tar -zcvf out/mynode_rootfs_rock64.tar.gz ./out/rootfs_rock64/*

### Make raspi3 rootfs ###
rsync -r -u rootfs/standard/* out/rootfs_raspi3/
rsync -r -u rootfs/raspi3/* out/rootfs_raspi3/
rsync -r -u CHANGELOG out/rootfs_raspi3/usr/share/mynode/changelog
rm -f out/mynode_rootfs_raspi3.tar.gz
tar -zcvf out/mynode_rootfs_raspi3.tar.gz ./out/rootfs_raspi3/*

### Make raspi4 rootfs ###
rsync -r -u rootfs/standard/* out/rootfs_raspi4/
rsync -r -u rootfs/raspi4/* out/rootfs_raspi4/
rsync -r -u CHANGELOG out/rootfs_raspi4/usr/share/mynode/changelog
rm -f out/mynode_rootfs_raspi4.tar.gz
tar -zcvf out/mynode_rootfs_raspi4.tar.gz ./out/rootfs_raspi4/*

### Make debian rootfs ###
rsync -r -u rootfs/standard/* out/rootfs_debian/
rsync -r -u rootfs/debian/* out/rootfs_debian/
rsync -r -u CHANGELOG out/rootfs_debian/usr/share/mynode/changelog
rm -f out/mynode_rootfs_debian.tar.gz
tar -zcvf out/mynode_rootfs_debian.tar.gz ./out/rootfs_debian/*
