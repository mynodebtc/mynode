#!/usr/bin/tclsh

proc checkPartitionForExistingMyNodeFs {partition} {
    if [catch {runCommand mount /dev/$partition /mnt/hdd}] {
        puts "Cannot mount partition ${partition}"
        return 0
    }
    if { [file exists /mnt/hdd/.mynode] } {
        puts "Found existing MyNode FS on ${partition}"
        runCommand echo /dev/${partition} > /tmp/.mynode_drive
        return 1
    }

    runCommand umount /mnt/hdd

    puts "No MyNode filesystem on existing partition ${partition}"
    return 0
}

proc checkPartitionsForExistingMyNodeFs {partitionsName} {
    upvar $partitionsName partitions
    runCommand mkdir -p /mnt/hdd

    # Check if we are skipping the check (to reformat drive)
    if { [file exists /home/bitcoin/.mynode/force_format_prompt] } {
        puts "Forcing format prompt (/home/bitcoin/.mynode/force_format_prompt exists)"
        return 0
    }

    # Check each partition
    foreach partition $partitions {
        if [checkPartitionForExistingMyNodeFs $partition] {
            # set partitions [lsearch -all -inline -not -exact $partitions $partition]
            return 1
        }
    }
    return 0
}


proc findBlockDevices {hardDrivesName} {
    upvar $hardDrivesName hardDrives
    set devs [exec ls /sys/block/]

    set hardDrives {}

    foreach dev $devs {
        if [regexp "sd.*|hd.*|vd.*|nvme.*" $dev] {
            # Check if drive mounted - command will fail if not mounted and get caught
            if {[catch { exec mount | grep $dev }]} {
                puts "Adding possible drive $dev"
                lappend hardDrives $dev
            } else {
                puts "Skipping drive $dev - already mounted"
            }
        }
    }
}

proc findAllPartitionsForBlockDevices {blockDevices partitionsName} {
    upvar $partitionsName partitions

    set partitions {}
    foreach dev $blockDevices {
        catch {
            set found [exec ls /sys/block/${dev}/ | grep ${dev}]
            foreach partition $found {
                lappend partitions $partition
            }
        }
    }
}

proc createMyNodeFsOnBlockDevice {blockDevice} {
    if [exec cat /sys/block/$blockDevice/ro] {
        puts "Cannot create MyNode partition on ${blockDevice} because it is read-only"
        return 0
    }

    if [catch {
        # Run USB check to make sure we are using a good driver
        runCommand /usr/local/bin/python3 /usr/bin/mynode_usb_driver_check.py > /dev/null

        puts "Waiting on format confirmation..."
        runCommand echo "drive_format_confirm" > /tmp/.mynode_status
        while { [file exists "/tmp/format_ok"] == 0 } {
            after 500
        }

        puts "Creating new partition table on ${blockDevice}"
        runCommand echo "drive_formatting" > /tmp/.mynode_status
        runCommand /usr/bin/format_drive.sh ${blockDevice}
        after 5000

        if [regexp "nvme.*" $blockDevice] {
            set blockPartition ${blockDevice}p1
        } else {
            set blockPartition ${blockDevice}1
        }

        puts "Formatting new partition ${blockPartition}"
        if [file exists "/tmp/format_filesystem_btrfs"] {
            runCommand mkfs.btrfs -f -L MyNode /dev/${blockPartition}
        } else {
            runCommand mkfs.ext4 -F -L MyNode /dev/${blockPartition}
        }

        #runCommand mount /dev/${blockPartition} /mnt/hdd -o errors=continue
        runCommand mount /dev/${blockPartition} /mnt/hdd
        runCommand date >/mnt/hdd/.mynode
        runCommand echo /dev/${blockPartition} > /tmp/.mynode_drive
    }] {
        puts "Formatting on ${blockDevice} failed: $::errorInfo"
        return 0
    }

    return 1
}

proc createMyNodeFsOrDie {blockDevices} {
    foreach dev $blockDevices {
        if [createMyNodeFsOnBlockDevice $dev] {
            return
        }
    }

    fatal "Cannot find a suitable drive for storing MyNode files"
}

proc runCommand {args} {
    #puts "Running:   ${args}"
    puts [exec -ignorestderr {*}$args]
}

proc mountFileSystems {} {
    findBlockDevices hardDrives
    set drive_count [llength $hardDrives]
    puts "Found these $drive_count drives: ${hardDrives}"


    findAllPartitionsForBlockDevices $hardDrives partitions
    puts "Found these existing drive partitions: ${partitions}"

    if {![checkPartitionsForExistingMyNodeFs partitions]} {
        puts "No existing drive found. Creating new one."
        createMyNodeFsOrDie $hardDrives
    }
}

if [catch {mountFileSystems}] {
    puts "No valid partition found. Try again."
    exit 1
}
exit 0