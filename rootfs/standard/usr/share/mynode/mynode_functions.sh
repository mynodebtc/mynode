#!/bin/bash

function should_install_app {
    if [ -f /home/bitcoin/.mynode/install_${1} ]; then
       return 0
    fi
    if [ -f /mnt/hdd/mynode/settings/install_${1} ]; then
       return 0
    fi
    return 1
}

function settings_file_exists {
    if [ -f /home/bitcoin/.mynode/${1} ]; then
       return 0
    fi
    if [ -f /mnt/hdd/mynode/settings/${1} ]; then
       return 0
    fi
    return 1
}

function skip_base_upgrades {
    if [ -f /tmp/skip_base_upgrades ]; then
        return 0
    fi
    return 1
}