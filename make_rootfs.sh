#!/bin/bash

# DEPRECATED DEVICES: raspi3

# Make each device
for i in 'raspi4' 'debian' 'rockpro64' 'rock64' 'rockpi4' ; do
	echo Creating root file system for $i
	mkdir -p out/rootfs_$i/

    # Clear out data for old apps
    rm -rf out/rootfs_$i/usr/share/mynode_apps

    # Make rootfs
	rsync -r -u rootfs/standard/* out/rootfs_$i/
	rsync -r -u rootfs/$i/* out/rootfs_$i/
	rsync -r -u CHANGELOG out/rootfs_$i/usr/share/mynode/changelog
	cp -f setup/setup_device.sh out/setup_device.sh
    #cp -f rootfs/standard/usr/share/mynode/mynode_app_versions.sh out/mynode_app_versions.sh

	rm -f out/mynode_rootfs_$i.tar.gz
	tar -zcf out/mynode_rootfs_$i.tar.gz out/rootfs_$i/*
done
echo Done!
