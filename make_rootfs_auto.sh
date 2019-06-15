#!/bin/bash

fswatch $(dirname $0)/rootfs | (while read; do $(dirname $0)/make_rootfs.sh; echo "Update rootfs!"; done)

