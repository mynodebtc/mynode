#!/bin/bash

for i in 'rock64' 'rockpro64' 'raspi3' 'raspi4' 'debian'; do
	mkdir -p out/rootfs_$i/
	rsync -r -u rootfs/standard/* out/rootfs_$i/
	rsync -r -u rootfs/$i/* out/rootfs_$i/
	rsync -r -u CHANGELOG out/rootfs_$i/usr/share/mynode/changelog
    cp -f setup/setup_device.sh out/setup_device.sh

	rm -f out/mynode_rootfs_$i.tar.gz
	tar -zcvf out/mynode_rootfs_$i.tar.gz ./out/rootfs_$i/*
done
