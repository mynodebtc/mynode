#!/bin/bash

# Catch ctrl-c to exit script - otherwise, loop just runs again
trap ctrl_c INT
function ctrl_c() {
    echo "Exiting..."
    exit 0
}

# Clear out any old rootfs copies
rm -rf $(dirname $0)/out/rootfs_*

# Did not work well on Linux.... works on OSX :-/
fswatch -o $(dirname $0)/rootfs $(dirname $0)/CHANGELOG | (while read; do $(dirname $0)/make_rootfs.sh; echo "Update rootfs!"; done)

# Worked on Linux and OSX (recently failing on OSX)
#while true; do find $(dirname $0)/rootfs/ | entr -d -s $(dirname $0)/make_rootfs.sh; done