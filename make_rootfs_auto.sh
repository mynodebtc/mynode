#!/bin/bash

rm -rf $(dirname $0)/out/rootfs_*

fswatch $(dirname $0)/rootfs $(dirname $0)/CHANGELOG | (while read; do $(dirname $0)/make_rootfs.sh; echo "Update rootfs!"; done)

