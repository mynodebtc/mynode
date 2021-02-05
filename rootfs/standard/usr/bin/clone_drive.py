#!/usr/bin/python3
import time
import os
import subprocess
import signal
import logging
from systemd import journal
from threading import Thread

log = logging.getLogger('mynode')
log.addHandler(journal.JournaldLogHandler())
log.setLevel(logging.INFO)

def print_and_log(msg):
    global log
    print(msg)
    log.info(msg)

def set_clone_state(state):
    print_and_log("Clone State: {}".format(state))
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

def set_clone_error(error_msg):
    print_and_log("Clone Error: {}".format(error_msg))
    try:
        with open("/tmp/.clone_error", "w") as f:
            f.write(error_msg)
        os.system("sync")
        return True
    except:
        return False
    return False

def check_pid(pid):        
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    else:
        return True

def send_usr1_sig(process_id):
    while check_pid(process_id):
        os.kill(process_id, signal.SIGUSR1)
        time.sleep(3)

def get_drive_size(drive):
    size = -1
    try:
        lsblk_output = subprocess.check_output(f"lsblk -b /dev/{drive} | grep disk", shell=True).decode("utf-8")
        parts = lsblk_output.split()
        size = int(parts[3])
    except:
        pass
    print_and_log(f"Drive {drive} size: {size}")
    return size


def check_partition_for_mynode(partition):
    is_mynode = False
    try:
        subprocess.check_output(f"mount -o ro /dev/{partition} /mnt/hdd", shell=True)
        if os.path.isfile("/mnt/hdd/.mynode"):
            is_mynode = True
    except Exception as e:
        # Mount failed, could be target drive
        pass
    finally:
        time.sleep(1)
        os.system("umount /mnt/hdd")

    return is_mynode

def find_partitions_for_drive(drive):
    partitions = []
    try:
        ls_output = subprocess.check_output(f"ls /sys/block/{drive}/ | grep {drive}", shell=True).decode("utf-8") 
        partitions = ls_output.split()
    except:
        pass
    return partitions

def is_drive_mounted(d):
    mounted = True
    try:
        # Command fails and throws exception if not mounted
        ls_output = subprocess.check_output(f"grep -qs '/dev/{d}' /proc/mounts", shell=True).decode("utf-8") 
    except:
        mounted = False
    return mounted

def find_drives():
    drives = []
    try:
        ls_output = subprocess.check_output("ls /sys/block/ | egrep 'hd.*|vd.*|sd.*|nvme.*'", shell=True).decode("utf-8") 
        all_drives = ls_output.split()

        # Only return drives that are not mounted (VM may have /dev/sda as OS drive)
        for d in all_drives:
            if not is_drive_mounted(d):
                drives.append(d)
    except:
        pass
    return drives

def main():
    # Set initial state
    set_clone_state("detecting")
    reset_clone_error()
    reset_clone_confirm()
    os.system("umount /mnt/hdd")
    os.system("rm /tmp/.clone_target_drive_has_mynode")

    # Detect drives
    drives = find_drives()
    print_and_log(f"Drives: {drives}")

    # Check exactly two drives found
    drive_count = len(drives)
    if drive_count != 2:
        print_and_log("Clone tool did not find 2 drives!")
        set_clone_state("error")
        set_clone_error("Clone tool needs 2 drives! Found {}.".format(drive_count))
        return

    # Detect Source and Target Drives
    mynode_drive = "not_found"
    mynode_found = False
    target_drive = "not_found"
    target_found = False
    both_drives_have_mynode = False
    for d in drives:
        partitions = find_partitions_for_drive(d)
        print_and_log(f"Drive {d} paritions: {partitions}")

        if len(partitions) == 0:
            # No partition found - must be target drive since its empty
            if target_found:
                set_clone_state("error")
                set_clone_error("Two target drives found. Is myNode drive missing?")
                return
            else:
                target_found = True
                target_drive = d
        elif len(partitions) > 1:
            # Multiple partitions found - myNode only uses one, so must be target
            if target_found:
                set_clone_state("error")
                set_clone_error("Two target drives found. Is myNode drive missing?")
                return
            else:
                target_found = True
                target_drive = d
        else:
            for p in partitions:
                a = round(time.time() * 1000)
                if check_partition_for_mynode(p):
                    if mynode_found:
                        # Second drive has myNode partition (failed clone?) - use size to determine target
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
                        print_and_log(f"myNode Partition Found: {p}")
                        mynode_drive = d
                        mynode_found = True
                else:
                    if target_found:
                        set_clone_state("error")
                        set_clone_error("Two target drives found. Is myNode drive missing?")
                        return
                    else:
                        target_found = True
                        target_drive = d
                b = round(time.time() * 1000)
                total_time = b - a
                print_and_log(f"Checked partition {p} in {total_time}ms")

    # Successfully found source and target, wait for confirm
    print_and_log(f"Source Drive: {mynode_drive}")
    print_and_log(f"Target Drive: {target_drive}")
    if both_drives_have_mynode:
        os.system("touch /tmp/.clone_target_drive_has_mynode")
    os.system(f"echo {mynode_drive} > /tmp/.clone_source")
    os.system(f"echo {target_drive} > /tmp/.clone_target")
    set_clone_state("need_confirm")
    while not os.path.isfile("/tmp/.clone_confirm"):
        time.sleep(1)

    # Clone drives
    set_clone_state("in_progress")
    os.system("echo 'Starting clone.' > /tmp/.clone_progress")
    try:
        cmd = ["dd","bs=64K",f"if=/dev/{mynode_drive}",f"of=/dev/{target_drive}","conv=sync,noerror"]
        #cmd = ["dd","bs=512",f"if=/dev/zero",f"of=/dev/null","count=5999999","conv=sync,noerror"]
        dd = subprocess.Popen(cmd, stderr=subprocess.PIPE)
        print_and_log("DD PID: {}".format(dd.pid))
        thread = Thread(target=send_usr1_sig, args=(dd.pid,))
        thread.start()
        for l in dd.stderr:
            l = l.decode("utf-8")
            if 'bytes' in l:
                try:
                    out_fd = open('/tmp/.clone_progress','w')
                    out_fd.write(l)
                    out_fd.close()
                except Exception as e:
                    print_and_log("Write Exception: " + str(e))

        while dd.poll() is None:
            time.sleep(5)
            print_and_log("Waiting on dd exit...")

        print_and_log("DD RET CODE: {}".format(dd.returncode))
        if dd.returncode != 0:
            # DD had an error - log it
            if dd.stderr != None:
                for l in dd.stderr:
                    print_and_log("DD STDERR: "+l.decode("utf-8"))
            if dd.stdout != None:
                for l in dd.stdout:
                    print_and_log("DD STDOUT: "+l.decode("utf-8"))
            set_clone_state("error")
            set_clone_error("DD failed with return code {}".format(dd.returncode))
            return
        print_and_log("DD IS COMPLETE")

        # PAUSE IF DD WAS SUCCESSFUL
        # if dd.returncode == 0:
        #     set_clone_state("error")
        #     set_clone_error("DD WAS SUCCESSFUL!!!! Remove temp code.")
        #     while True:
        #         time.sleep(60)
        
        # Update partitions (removes all + makes new without removing data)
        print_and_log("Updating Partitions...")
        os.system("echo 'Updating partitions...' > /tmp/.clone_progress")
        subprocess.check_output(f"/usr/bin/format_drive.sh {target_drive}", shell=True)
        time.sleep(2)

        # Resize filesystem to fill up whole drive
        print_and_log("Resizing Filesystem...")
        os.system("echo 'Resizing filesystem...' > /tmp/.clone_progress")
        os.system(f"partprobe /dev/{target_drive}")
        time.sleep(2)
        subprocess.check_output(f"e2fsck -y -f /dev/{target_drive}1", shell=True)
        subprocess.check_output(f"resize2fs /dev/{target_drive}1", shell=True)
    except subprocess.CalledProcessError as e:
        print_and_log("CalledProcessError")
        print_and_log(e.stderr)
        print_and_log(e.stdout)
        set_clone_state("error")
        set_clone_error("Clone failed: {}".format(e))
        return
    except Exception as e:
        set_clone_state("error")
        set_clone_error("Clone failed: {}".format(e))
        return
        

    # Complete - wait for reboot
    set_clone_state("complete")
    print_and_log("Clone Complete!")
    print_and_log("Waiting for reboot...")
    while True:
        time.sleep(60)
    

# This is the main entry point for the program
if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print_and_log("Exception: {}".format(str(e)))
        set_clone_error("Exception: {}".format(str(e)))