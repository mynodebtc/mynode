#!/bin/bash

fswatch $(dirname $0)/rootfs $(dirname $0)/CHANGELOG | (while read; do $(dirname $0)/make_rootfs.sh; echo "Update rootfs!"; done)

