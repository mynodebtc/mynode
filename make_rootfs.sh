#!/bin/bash

### Clear existing rootfs ###
rm -rf out/rootfs*
mkdir -p out/rootfs_rock64/
mkdir -p out/rootfs_raspi/

### Make rock64 rootfs ###
cp -rf rootfs/standard/* out/rootfs_rock64/

### Make raspi rootfs ###
cp -rf rootfs/standard/* out/rootfs_raspi/
cp -rf rootfs/raspi/* out/rootfs_raspi/

### Make tarballs ###
rm -f out/mynode_rootfs_raspi.tar.gz
rm -f out/mynode_rootfs_rock64.tar.gz
tar -zcvf out/mynode_rootfs_raspi.tar.gz ./out/rootfs_raspi/*
tar -zcvf out/mynode_rootfs_rock64.tar.gz ./out/rootfs_rock64/*