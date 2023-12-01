#!/usr/local/bin/python3
import time
import os
import subprocess
import logging
from systemd import journal
from utilities import *
from drive_info import *

log = logging.getLogger('mynode')
log.addHandler(journal.JournaldLogHandler())
log.setLevel(logging.INFO)
set_logger(log)

def set_clone_state(state):
    log_message("Clone State: {}".format(state))
    try:
        with open("/tmp/.clone_state", "w") as f:
            f.write(state)
        os.system("sync")
        return True
    except:
        return False
    return False

def reset_clone_error():
    os.system("rm /tmp/.clone_error")

def reset_clone_confirm():
    os.system("rm /tmp/.clone_confirm")

def reset_clone_rescan():
    os.system("rm /tmp/.clone_rescan")

def set_clone_error(error_msg):
    log_message("Clone Error: {}".format(error_msg))
    try:
        with open("/tmp/.clone_error", "w") as f:
            f.write(error_msg)
        os.system("sync")
        return True
    except:
        return False
    return False

def wait_on_clone_error_dismiss():
    while os.path.isfile("/tmp/.clone_error"):
        time.sleep(1)


def main():
    # Set initial state
    set_clone_state("detecting")
    reset_clone_error()
    reset_clone_confirm()
    reset_clone_rescan()
    os.system("umount /mnt/hdd")
    os.system("umount /tmp/drive1")
    os.system("umount /tmp/drive2")
    os.system("rm /tmp/.clone_target_drive_has_mynode")

    # Detect drives
    drives = find_unmounted_drives()
    log_message(f"Drives: {drives}")

    # Check exactly two drives found
    drive_count = len(drives)
    if drive_count != 2:
        log_message("Clone tool did not find 2 drives!")
        set_clone_state("error")
        set_clone_error("Clone tool needs 2 drives! Found {}.".format(drive_count))
        wait_on_clone_error_dismiss()
        return

    # Detect Source and Target Drives
    mynode_drive = "not_found"
    mynode_found = False
    target_drive = "not_found"
    target_found = False
    both_drives_have_mynode = False
    for d in drives:
        partitions = find_partitions_for_drive(d)
        log_message(f"Drive {d} paritions: {partitions}")

        if len(partitions) == 0:
            # No partition found - must be target drive since its empty
            if target_found:
                set_clone_state("error")
                set_clone_error("Two target drives found. Is MyNode drive missing?")
                wait_on_clone_error_dismiss()
                return
            else:
                target_found = True
                target_drive = d
        elif len(partitions) > 1:
            # Multiple partitions found - MyNode only uses one, so must be target
            if target_found:
                set_clone_state("error")
                set_clone_error("Two target drives found. Is MyNode drive missing?")
                wait_on_clone_error_dismiss()
                return
            else:
                target_found = True
                target_drive = d
        else:
            for p in partitions:
                a = round(time.time() * 1000)
                if check_partition_for_mynode(p):
                    if mynode_found:
                        # Second drive has MyNode partition (failed clone?) - use size to determine target
                        both_drives_have_mynode = True
                        drive_1_size = get_drive_size(mynode_drive)
                        drive_2_size = get_drive_size(d)
                        if drive_2_size >= drive_1_size:
                            mynode_drive = mynode_drive
                            target_drive = d
                        else:
                            target_drive = mynode_drive
                            mynode_drive = d
                        target_found = True
                    else:
                        log_message(f"MyNode Partition Found: {p}")
                        mynode_drive = d
                        mynode_found = True
                else:
                    if target_found:
                        set_clone_state("error")
                        set_clone_error("Two target drives found. Is MyNode drive missing?")
                        wait_on_clone_error_dismiss()
                        return
                    else:
                        target_found = True
                        target_drive = d
                b = round(time.time() * 1000)
                total_time = b - a
                log_message(f"Checked partition {p} in {total_time}ms")

    # Successfully found source and target, wait for confirm
    log_message(f"Source Drive: {mynode_drive}")
    log_message(f"Target Drive: {target_drive}")
    if both_drives_have_mynode:
        os.system("touch /tmp/.clone_target_drive_has_mynode")
    os.system(f"echo {mynode_drive} > /tmp/.clone_source")
    os.system(f"echo {target_drive} > /tmp/.clone_target")
    set_clone_state("need_confirm")
    while not os.path.isfile("/tmp/.clone_confirm") and not os.path.isfile("/tmp/.clone_rescan"):
        time.sleep(1)

    # User asked for rescan, return, script will re-run right away
    if os.path.isfile("/tmp/.clone_rescan"):
        return

    # Setup for clone
    set_clone_state("in_progress")
    os.system(f"mkdir -p /tmp/drive1")
    os.system(f"mkdir -p /tmp/drive2")
    os.system(f"umount /dev/{mynode_drive}1")
    os.system(f"umount /dev/{target_drive}1")

    # Update partitions (removes all + makes new without removing data)
    log_message("Formatting Drive...")
    os.system("echo 'Formatting drive...' > /tmp/.clone_progress")
    subprocess.check_output(f"wipefs -a /dev/{target_drive}", shell=True)
    time.sleep(2)
    subprocess.check_output(f"/usr/bin/format_drive.sh {target_drive}", shell=True)
    time.sleep(2)

    # Make new partition on dest drive
    log_message("Creating Partition...")
    os.system("echo 'Creating Partition...' > /tmp/.clone_progress")
    subprocess.check_output(f"mkfs.ext4 -F -L MyNode /dev/{target_drive}1", shell=True)
    time.sleep(2)

    # Mounting Partitions
    log_message("Mounting Partitions...")
    os.system("echo 'Mounting Partitions...' > /tmp/.clone_progress")
    subprocess.check_output(f"mount /dev/{mynode_drive}1 /tmp/drive1", shell=True)
    subprocess.check_output(f"mount /dev/{target_drive}1 /tmp/drive2", shell=True)

    # Clone drives
    os.system("echo 'Starting clone.' > /tmp/.clone_progress")
    try:
        #cmd = ["dd","bs=64K",f"if=/dev/{mynode_drive}",f"of=/dev/{target_drive}","conv=sync,noerror"]
        #cmd = ["dd","bs=512",f"if=/dev/zero",f"of=/dev/null","count=5999999","conv=sync,noerror"]
        cmd = ["rsync","-avxHAX","--info=progress2",f"/tmp/drive1/","/tmp/drive2/"]
        clone_process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        log_message("CLONE PID: {}".format(clone_process.pid))
        for l in clone_process.stdout:
            l = l.decode("utf-8")
            if 'xfr#' in l:
                logline = "UNKNOWN"
                try:
                    lines = l.split("\r")
                    logline = lines[len(lines)-1].strip()
                    parts = logline.split()
                    logline = parts[0] + " bytes copied<br/>" + parts[1] + "<br/>" + parts[2] + "<br/>" + parts[3]
                except Exception as e:
                    logline = "Clone status parse error: ".format(str(e))
                try:
                    out_fd = open('/tmp/.clone_progress','w')
                    out_fd.write(logline)
                    out_fd.close()
                except Exception as e:
                    log_message("Write Exception: " + str(e))

        while clone_process.poll() is None:
            time.sleep(5)
            log_message("Waiting on rsync exit...")

        log_message("CLONE RET CODE: {}".format(clone_process.returncode))
        if clone_process.returncode != 0:
            # Clone had an error - log it
            if clone_process.stderr != None:
                for l in clone_process.stderr:
                    log_message("CLONE STDERR: "+l.decode("utf-8"))
            if clone_process.stdout != None:
                for l in clone_process.stdout:
                    log_message("CLONE STDOUT: "+l.decode("utf-8"))
            set_clone_state("error")
            set_clone_error("Clone failed with return code {}".format(clone_process.returncode))
            wait_on_clone_error_dismiss()
            return

        log_message("CLONE IS COMPLETE")
        time.sleep(2)
    except subprocess.CalledProcessError as e:
        log_message("CalledProcessError")
        log_message(e.stderr)
        log_message(e.stdout)
        set_clone_state("error")
        set_clone_error("Clone failed: {}".format(e))
        wait_on_clone_error_dismiss()
        return
    except Exception as e:
        set_clone_state("error")
        set_clone_error("Clone failed: {}".format(e))
        wait_on_clone_error_dismiss()
        return
        
    # Complete - wait for reboot
    set_clone_state("complete")
    log_message("Clone Complete!")
    log_message("Waiting for reboot...")
    while True:
        time.sleep(60)
    

# This is the main entry point for the program
if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log_message("Exception: {}".format(str(e)))
        set_clone_error("Exception: {}".format(str(e)))
        wait_on_clone_error_dismiss()