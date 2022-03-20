#!/usr/local/bin/python3
import os
import requests
import time
import subprocess
import logging
import shutil
from utilities import *
from drive_info import *
from device_info import *
from inotify_simple import INotify, flags
from systemd import journal
import random

BACKUP_SCB_URL = "https://www.mynodebtc.com/device_api/backup_scb.php"

LND_MAINNET_CHANNEL_FILE        = "/mnt/hdd/mynode/lnd/data/chain/bitcoin/mainnet/channel.backup"
LND_MAINNET_CHANNEL_FILE_BACKUP = "/home/bitcoin/lnd_backup/channel.backup"
LND_TESTNET_CHANNEL_FILE        = "/mnt/hdd/mynode/lnd/data/chain/bitcoin/testnet/channel.backup"
LND_TESTNET_CHANNEL_FILE_BACKUP = "/home/bitcoin/lnd_backup/channel_testnet.backup"


log = logging.getLogger('lndbackup')
log.addHandler(journal.JournaldLogHandler())
log.setLevel(logging.INFO)
set_logger(log)

# Helper functions
cached_remote_hash = "NONE"
def get_saved_remote_backup_hash():
    global cached_remote_hash
    return cached_remote_hash
def set_saved_remote_backup_hash(hash):
    global cached_remote_hash
    cached_remote_hash = hash

# Local Backup
def local_backup(original_scb, backup_scb):
    if os.path.isfile(original_scb):
        md5_1 = get_md5_file_hash(original_scb)
        md5_2 = "REPLACE_FILE"
        if os.path.isfile(backup_scb):
            md5_2 = get_md5_file_hash(backup_scb)

        log_message("  Hash 1: {}".format(md5_1))
        log_message("  Hash 2: {}".format(md5_2))
        
        # If file is missing or different, back it up!
        if md5_1 != md5_2:
            shutil.copyfile(original_scb, backup_scb)
            log_message("Local Backup: Backup Updated!")
        else:
            log_message("Local Backup: Hashes Match. Skipping Backup.")
    else:
        log_message("Local Backup: Missing File")

# Remote Backup
def remote_backup(original, backup):

    # Check if remote backup is enabled
    premium_plus_settings = get_premium_plus_settings()
    if not premium_plus_settings['backup_scb']:
        log_message("Remote Backup: SCB Backup Disabled")
        return

    # Mainnet only
    if is_testnet_enabled():
        log_message("Remote Backup: Skipping (testnet enabled)")
        return

    # Premium+ Feature
    if not has_premium_plus_token() or get_premium_plus_token_status() != "OK":
        log_message("Remote Backup: Skipping (not Premium+)")
        return

    md5_1 = get_md5_file_hash(original_scb)
    md5_2 = get_saved_remote_backup_hash()
    log_message("  Hash 1: {}".format(md5_1))
    log_message("  Hash 2: {}".format(md5_2))
    if md5_1 == md5_2:
        log_message("Remote Backup: Hashes Match. Skipping Backup.")
        return

    # POST Data
    try:
        file_data = {'scb': open(original,'rb')}
    except Exception as e:
        log_message("Remote Backup: Error reading SCB file.")
        return

    data = {
        "token": get_premium_plus_token(),
        "product_key": get_product_key()
    }

    response = make_tor_request(BACKUP_SCB_URL, data, file_data)
    if response == None:
        log_message("Premium+ Connect Error: Connection Failed")
        return False
    if response.status_code != 200:
        log_message("Remote Backup: Connect Failed. Code {}".format(response.status_code))
        return False
    else:
        if response.text == "OK":
            log_message("Remote Backup: Success ({})".format(response.text))
            set_saved_remote_backup_hash( md5_1 )
        else:
            log_message("Remote Backup: Error: ({})".format(response.text))

    return True

def backup(original_scb, backup_scb):
    log_message("Backing up SCB file...")
    local_backup(original_scb, backup_scb)
    remote_backup(original_scb, backup_scb)
    log_message("Backup Complete.")

# Backup SCB file
if __name__ == "__main__":
    one_hour_in_ms = 60 * 60 * 1000

    while True:
        try:
            # Wait for drive to be mounted
            while not is_mynode_drive_mounted():
                log_message("Checking if drive mounted...")
                time.sleep(10)
            log_message("Drive mounted!")

            # Determine backup file
            original_scb = LND_MAINNET_CHANNEL_FILE
            backup_scb = LND_MAINNET_CHANNEL_FILE_BACKUP
            if is_testnet_enabled():
                original_scb = LND_TESTNET_CHANNEL_FILE
                backup_scb = LND_TESTNET_CHANNEL_FILE_BACKUP

            # Perform backup
            backup(original_scb, backup_scb)

            # Watch for updates
            inotify = INotify()
            watch_flags = flags.CREATE | flags.DELETE | flags.MODIFY | flags.DELETE_SELF
            wd = inotify.add_watch(original_scb, watch_flags)
            for event in inotify.read(timeout=one_hour_in_ms):
                log_message("File changed: " + str(event))
        except Exception as e:
            log_message("Error: {}".format(e))
            time.sleep(60)
