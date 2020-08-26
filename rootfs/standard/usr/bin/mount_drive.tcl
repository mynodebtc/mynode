#!/usr/bin/tclsh

proc checkPartitionForExistingMyNodeFs {partition} {
    if [catch {runCommand mount /dev/$partition /mnt/hdd}] {
        puts "Cannot mount partition ${partition}"
        return 0
    }
    if { [file exists /mnt/hdd/.mynode] } {
        puts "Found existing myNode FS on ${partition}"
        runCommand echo /dev/${partition} > /tmp/.mynode_drive
        return 1
    }

    runCommand umount /mnt/hdd

    puts "No myNode filesystem on existing partition ${partition}"
    return 0
}

proc checkPartitionsForExistingMyNodeFs {partitionsName} {
    upvar $partitionsName partitions
    runCommand mkdir -p /mnt/hdd
    foreach partition $partitions {
        if [checkPartitionForExistingMyNodeFs $partition] {
            # Remove this partition from the list so we don't try to
            # use it as the config drive later on.
            set partitions [lsearch -all -inline -not -exact $partitions $partition]

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
        puts "Cannot create myNode partition on ${blockDevice} because it is read-only"
        return 0
    }

    if [catch {
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
        runCommand mkfs.ext4 -F -L myNode /dev/${blockPartition}

        runCommand mount /dev/${blockPartition} /mnt/hdd -o errors=continue
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

    fatal "Cannot find a suitable drive for storing myNode files"
}

proc runCommand {args} {
    #puts "Running:   ${args}"
    puts [exec -ignorestderr {*}$args]
}

proc mountFileSystems {} {
    findBlockDevices hardDrives

    puts "Found these harddrives: ${hardDrives}"

    findAllPartitionsForBlockDevices $hardDrives partitions
    puts "Found these existing harddrive partitions: ${partitions}"

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