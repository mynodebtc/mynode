#!/bin/bash

### Clear existing rootfs ###
rm -rf out/rootfs*
mkdir -p out/rootfs_rock64/
mkdir -p out/rootfs_raspi/

### Make rock64 rootfs ###
cp -rf rootfs/standard/* out/rootfs_rock64/

#### Make raspi rootfs ###
cp -rf rootfs/standard/* out/rootfs_raspi/
cp -rf rootfs/raspi/* out/rootfs_raspi/
