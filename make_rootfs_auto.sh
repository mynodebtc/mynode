#!/bin/bash

rm -rf $(dirname $0)/out/rootfs_*

# Did not work well on Linux.... works on OSX :-/
#fswatch -o $(dirname $0)/rootfs $(dirname $0)/CHANGELOG | (while read; do $(dirname $0)/make_rootfs.sh; echo "Update rootfs!"; done)

while true; do find $(dirname $0)/rootfs/ | entr -d -s $(dirname $0)/make_rootfs.sh; done