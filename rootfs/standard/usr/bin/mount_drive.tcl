#!/usr/bin/tclsh

proc checkPartitionForExistingMyNodeFs {partition} {
    if [catch {runCommand mount /dev/$partition /mnt/hdd}] {
        puts "Cannot mount partition ${partition}"
        return 0
    }
    if { [file exists /mnt/hdd/.mynode] || [file isdirectory /mnt/hdd/mynode] } {
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
        if [regexp "sd.*|hd.*|vd.*" $dev] {
            lappend hardDrives $dev
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
        puts "Creating new partition table on ${blockDevice}"
        runCommand /usr/bin/format_drive.sh ${blockDevice}
        after 5000

        puts "Formatting new partition ${blockDevice}1"
        runCommand mkfs.ext4 -F -L myNode /dev/${blockDevice}1

        runCommand mount /dev/${blockDevice}1 /mnt/hdd -o errors=continue
        runCommand date >/mnt/hdd/.mynode
        runCommand echo /dev/${blockDevice}1 > /tmp/.mynode_drive
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