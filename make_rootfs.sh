#!/bin/bash

### Clear existing rootfs ###
rm -rf out/rootfs*
mkdir -p out/rootfs_rock64/
mkdir -p out/rootfs_raspi3/
mkdir -p out/rootfs_raspi4/


### Make rock64 rootfs ###
cp -rf rootfs/standard/* out/rootfs_rock64/
rm -f out/mynode_rootfs_rock64.tar.gz
tar -zcvf out/mynode_rootfs_rock64.tar.gz ./out/rootfs_rock64/*

### Make raspi3 rootfs ###
cp -rf rootfs/standard/* out/rootfs_raspi3/
cp -rf rootfs/raspi3/* out/rootfs_raspi3/
rm -f out/mynode_rootfs_raspi3.tar.gz
tar -zcvf out/mynode_rootfs_raspi3.tar.gz ./out/rootfs_raspi3/*

### Make raspi4 rootfs ###
cp -rf rootfs/standard/* out/rootfs_raspi4/
cp -rf rootfs/raspi4/* out/rootfs_raspi4/
rm -f out/mynode_rootfs_raspi4.tar.gz
tar -zcvf out/mynode_rootfs_raspi4.tar.gz ./out/rootfs_raspi4/*
