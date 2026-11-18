#!/bin/bash

# Upgrades the OS one Debian release (10 -> 11, 11 -> 12), then runs MyNode's post upgrade script
# so the device ends where a fresh image of the new release would, and reboots. The data drive is
# not changed. Run it again after the reboot to go up another release.
#
# Started from Settings as a transient systemd unit (see os_upgrade.py), so it keeps running when
# the web UI restarts. Exits non-zero without rebooting when something fails; running it again
# finishes an interrupted upgrade.

source /usr/share/mynode/mynode_device_info.sh
source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_functions.sh

LOG_DIR=/home/admin/upgrade_logs
LOG_FILE=$LOG_DIR/upgrade_log_os_release.txt
ERROR_FILE=/home/bitcoin/.mynode/os_release_upgrade_error
# Release being upgraded to. Kept until the upgrade finishes, since an interrupted upgrade can
# leave /etc/os-release already showing the new release.
TARGET_FILE=/home/bitcoin/.mynode/os_release_upgrade_target
# Read by mynode_post_upgrade.sh, which then rebuilds MyNode's Python against the new libraries
PYTHON_REBUILD_FILE=/home/bitcoin/.mynode/rebuild_python
APT_ARCHIVES=/mnt/hdd/mynode/apt_archives_os_upgrade

mkdir -p $LOG_DIR
# Also copied to upgrade_log_latest.txt, which the upgrade wait page shows
exec > >(tee $LOG_DIR/upgrade_log_latest.txt > $LOG_FILE) 2>&1
chown -R admin:admin $LOG_DIR

function fail {
    echo "OS upgrade failed: $1"
    touch $ERROR_FILE
    rm -f /tmp/upgrade_started /tmp/mark_reboot___upgrade_os_release
    chown -R admin:admin $LOG_DIR
    exit 1
}

set -x
date
rm -f $ERROR_FILE

# Releases this script can upgrade to, by current Debian version
declare -A NEXT_CODENAME=( [10]="bullseye" [11]="bookworm" )
declare -A CODENAME_VERSION=( [buster]=10 [bullseye]=11 [bookworm]=12 )

# Supported devices: 64-bit Raspberry Pi 4 and 5, and amd64
if [ "$IS_64_BIT" != "1" ] || [[ ! "$DEVICE_TYPE" =~ ^(raspi4|raspi5|debian)$ ]]; then
    fail "OS upgrades are not supported on this device ($DEVICE_TYPE, $DEVICE_ARCH)"
fi

CURRENT_CODENAME=$DEBIAN_CODENAME
if [ -f $TARGET_FILE ]; then
    TARGET=$(cat $TARGET_FILE)
    echo "Continuing an earlier upgrade to $TARGET"
else
    TARGET=${NEXT_CODENAME[$DEBIAN_VERSION]}
fi
if [ -z "$TARGET" ] || [ -z "${CODENAME_VERSION[$TARGET]}" ]; then
    fail "Debian $DEBIAN_VERSION ($DEBIAN_CODENAME) is already the latest release supported for OS upgrades"
fi
TARGET_VERSION=${CODENAME_VERSION[$TARGET]}
OLD_CODENAME=""
for c in "${!CODENAME_VERSION[@]}"; do
    [ "${CODENAME_VERSION[$c]}" = "$((TARGET_VERSION - 1))" ] && OLD_CODENAME=$c
done
echo "Upgrading from Debian $OLD_CODENAME to $TARGET (running $CURRENT_CODENAME)"

# Pre-checks
mountpoint -q /mnt/hdd || fail "The data drive is not mounted"
ROOT_FREE_MB=$(df -m --output=avail / | tail -n 1 | tr -d ' ')
if [ "$ROOT_FREE_MB" -lt 1500 ]; then
    fail "Only ${ROOT_FREE_MB} MB free on the OS drive. At least 1500 MB is needed."
fi
HDD_FREE_MB=$(df -m --output=avail /mnt/hdd | tail -n 1 | tr -d ' ')
if [ "$HDD_FREE_MB" -lt 5000 ]; then
    fail "Only ${HDD_FREE_MB} MB free on the data drive. At least 5000 MB is needed."
fi

# Stop MyNode's services to free memory, and keep automatic OS updates and MyNode auto-upgrades out
echo "upgrading" > $MYNODE_STATUS_FILE
touch /tmp/upgrade_started
/usr/bin/mynode_stop_critical_services.sh
pause_automatic_os_updates
trap "systemctl start apt-daily.timer apt-daily-upgrade.timer > /dev/null 2>&1 || true" EXIT

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export UCF_FORCE_CONFFOLD=1
# Downloads go to the data drive, since the OS drive is often nearly full
mkdir -p $APT_ARCHIVES/partial
APT_OPTIONS="-o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o Dir::Cache::archives=$APT_ARCHIVES/"

# Finish any interrupted package installs on the current release
dpkg --configure -a --force-confdef --force-confold || fail "dpkg --configure -a failed"

# Point the package sources at the new release. A copy of the old ones is kept in /var/backups.
if [ ! -f $TARGET_FILE ]; then
    tar czf /var/backups/mynode_apt_sources_${OLD_CODENAME}.tar.gz /etc/apt/sources.list /etc/apt/sources.list.d || true
    echo $TARGET > $TARGET_FILE
fi

# Raspberry Pi OS 12 mounts the boot partition at /boot/firmware and boots the Debian-style
# linux-image-rpi-* kernels, which the raspi-firmware package copies there. A Pi 4 that started on
# Debian 10 or 11 mounts it at /boot and boots the old raspberrypi-kernel package, which apt never
# replaces on its own, so the upgrade to 12 moves it to the new layout.
RPI_BOOT_CONVERT=0
EXTRA_PACKAGES=""
BOOT_FW=/boot/firmware
RPI_KERNEL_PACKAGES="linux-image-rpi-v8 raspi-firmware"
RPI_OLD_KERNEL_PACKAGES="raspberrypi-kernel raspberrypi-bootloader"
RPI_UTIL_PACKAGES="raspi-utils rpi-eeprom raspinfo"
BOOT_BACKUP=/var/backups/mynode_boot_partition_${OLD_CODENAME}.tar.gz
if [ "$IS_RASPI4" = 1 ] && [ "$TARGET_VERSION" = 12 ]; then
    RPI_BOOT_CONVERT=1
    EXTRA_PACKAGES="$RPI_KERNEL_PACKAGES"
fi

function is_installed {
    dpkg-query -W -f='${Status}' $1 2>/dev/null | grep -q "ok installed"
}

# Mount the boot partition at /boot/firmware. The firmware doesn't care where it is mounted, so the
# device still boots its old kernel from it. raspi-firmware won't install unless it is mounted there.
function move_rpi_boot_partition {
    mountpoint -q $BOOT_FW && return 0
    findmnt -no FSTYPE /boot | grep -q vfat || fail "The boot partition is not mounted at /boot"
    BOOT_FREE_MB=$(df -m --output=avail /boot | tail -n 1 | tr -d ' ')
    if [ "$BOOT_FREE_MB" -lt 100 ]; then
        fail "Only ${BOOT_FREE_MB} MB free on the boot partition. At least 100 MB is needed."
    fi
    tar czf $BOOT_BACKUP -C /boot . || fail "Backing up the boot partition failed"
    cp -a /etc/fstab /var/backups/mynode_fstab_${OLD_CODENAME}
    sed -i -E "s|^([^#[:space:]]+[[:space:]]+)/boot([[:space:]]+vfat[[:space:]])|\1$BOOT_FW\2|" /etc/fstab
    grep -qE "^[^#[:space:]]+[[:space:]]+$BOOT_FW[[:space:]]+vfat[[:space:]]" /etc/fstab || \
        fail "Moving the boot partition in /etc/fstab failed"
    systemctl daemon-reload
    sync
    if ! umount /boot; then
        cp -a /var/backups/mynode_fstab_${OLD_CODENAME} /etc/fstab
        systemctl daemon-reload
        fail "Unmounting /boot failed"
    fi
    mkdir -p $BOOT_FW
    if ! mount $BOOT_FW; then
        cp -a /var/backups/mynode_fstab_${OLD_CODENAME} /etc/fstab
        systemctl daemon-reload
        mount /boot
        fail "Mounting the boot partition at $BOOT_FW failed"
    fi
}

# Checks that the next boot uses the new kernel. Prints what is wrong and returns non-zero.
function check_rpi_boot_files {
    local ok=0 kver f p
    mountpoint -q $BOOT_FW || { echo "$BOOT_FW is not mounted"; ok=1; }
    grep -qE "^[^#[:space:]]+[[:space:]]+$BOOT_FW[[:space:]]+vfat[[:space:]]" /etc/fstab || \
        { echo "$BOOT_FW is not in /etc/fstab"; ok=1; }
    for p in $RPI_KERNEL_PACKAGES; do
        is_installed $p || { echo "$p is not installed"; ok=1; }
    done
    kver=$(ls /boot/vmlinuz-*-rpi-v8 2>/dev/null | sort -V | tail -n 1 | sed 's#^/boot/vmlinuz-##')
    if [ -z "$kver" ] || ! cmp -s /boot/vmlinuz-$kver $BOOT_FW/kernel8.img; then
        echo "$BOOT_FW/kernel8.img is not the new kernel ($kver)"; ok=1
    fi
    if [ -z "$kver" ] || [ ! -d /lib/modules/$kver ]; then
        echo "The modules for kernel $kver are missing"; ok=1
    fi
    for f in initramfs8 bcm2711-rpi-4-b.dtb start4.elf fixup4.dat config.txt cmdline.txt; do
        [ -s $BOOT_FW/$f ] || { echo "$BOOT_FW/$f is missing"; ok=1; }
    done
    grep -q "^arm_64bit=1" $BOOT_FW/config.txt || { echo "config.txt does not set arm_64bit=1"; ok=1; }
    ROOT_ARG=$(grep -o "root=[^ ]*" /proc/cmdline)
    grep -qF "$ROOT_ARG" $BOOT_FW/cmdline.txt || { echo "cmdline.txt does not have $ROOT_ARG"; ok=1; }
    return $ok
}

# Installs the new kernel, after the rest of the OS is on the new release
function install_rpi_kernel {
    apt-get $APT_OPTIONS -y install $RPI_KERNEL_PACKAGES || fail "Installing the new Raspberry Pi kernel failed"
    # Fresh images load the new kernel's initramfs
    if ! grep -q "^auto_initramfs=1" $BOOT_FW/config.txt; then
        sed -i '1i auto_initramfs=1' $BOOT_FW/config.txt
    fi
    if ! check_rpi_boot_files; then
        # Put the old kernel and firmware back, so the device still boots the old kernel
        sed -i '/^auto_initramfs=1$/d' $BOOT_FW/config.txt
        [ -f $BOOT_BACKUP ] && tar xzf $BOOT_BACKUP -C $BOOT_FW
        fail "The new kernel was not set up on the boot partition"
    fi
}

# The upgrade removes the Raspberry Pi tools (vcgencmd, rpi-eeprom), which conflict with the old
# libraspberrypi packages. Install them like fresh images, which have no libraspberrypi packages.
function install_rpi_utils {
    local others
    others=$(apt-get -s install $RPI_UTIL_PACKAGES | awk '/^(Purg|Remv) /{print $2}' | grep -vE "^libraspberrypi")
    if [ -n "$others" ]; then
        echo "Not installing $RPI_UTIL_PACKAGES, since it would also remove: $others"
        return 0
    fi
    apt-get $APT_OPTIONS -y install $RPI_UTIL_PACKAGES || echo "Installing $RPI_UTIL_PACKAGES failed"
}

# Removes the old kernel packages and finishes the layout of fresh images. Runs last, because the
# old kernel is still running until the reboot and removing it deletes its modules.
function remove_old_rpi_kernel {
    local pkgs="" p f others
    for p in $RPI_OLD_KERNEL_PACKAGES; do
        is_installed $p && pkgs="$pkgs $p"
    done
    if [ -n "$pkgs" ]; then
        others=$(apt-get -s purge $pkgs | awk '/^(Purg|Remv) /{print $2}' | grep -vxE "raspberrypi-kernel|raspberrypi-bootloader")
        if [ -n "$others" ]; then
            echo "Keeping the old kernel packages, since removing them would also remove: $others"
        else
            apt-get -o DPkg::Lock::Timeout=300 -y purge $pkgs || echo "Removing the old kernel packages failed"
        fi
    fi
    # Like fresh images: /boot/overlays links to the boot partition, and notes where config.txt and
    # cmdline.txt moved. Done after the purge, which deletes the old package's files in /boot/overlays.
    if [ -d /boot/overlays ] && [ ! -L /boot/overlays ]; then
        rmdir /boot/overlays 2>/dev/null || true
    fi
    [ -e /boot/overlays ] || ln -s firmware/overlays /boot/overlays
    for f in config.txt cmdline.txt; do
        [ -e /boot/$f ] || printf 'DO NOT EDIT THIS FILE\n\nThe file you are looking for has moved to %s\n' "$BOOT_FW/$f" > /boot/$f
    done
}

if [ $RPI_BOOT_CONVERT = 1 ]; then
    move_rpi_boot_partition
fi

COMPONENTS="main contrib non-free"
if [ "$TARGET_VERSION" -ge 12 ]; then
    COMPONENTS="main contrib non-free non-free-firmware"
fi
function write_debian_sources {
    cat > /etc/apt/sources.list << EOF
deb $1 $TARGET $COMPONENTS
deb $2 $TARGET-security $COMPONENTS
deb $1 $TARGET-updates $COMPONENTS
EOF
}

# Third-party sources (Raspberry Pi, Tailscale, Docker, ...) name the release. MyNode's post upgrade
# script rewrites the Tor, I2P, NodeSource and Docker sources for the new release.
for f in /etc/apt/sources.list.d/*.list; do
    [ -f "$f" ] && sed -i -E "s/([ /])${OLD_CODENAME}([ /]|$)/\1${TARGET}\2/g" "$f"
done

# GRUB is held by OS package upgrades, but has to move to the new release with the rest of the OS
if [ $IS_X86 = 1 ]; then
    apt-mark unhold 'grub*' || true
    # grub-pc installs to the disks it has saved, and fails when none of them exist. Flashed images
    # have the disk of the machine that built the image saved, or none, so use the disk / is on.
    if dpkg-query -W -f='${Status}' grub-pc 2>/dev/null | grep -qE "ok (installed|half-configured|unpacked)"; then
        GRUB_DISK_FOUND=0
        for d in $(debconf-show grub-pc 2>/dev/null | sed -n 's/.*grub-pc\/install_devices: *//p' | tr ',' ' '); do
            [ -e "$d" ] && GRUB_DISK_FOUND=1
        done
        ROOT_DISK=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" | head -n 1)
        if [ $GRUB_DISK_FOUND = 0 ] && [ -n "$ROOT_DISK" ]; then
            echo "Setting the GRUB install disk to /dev/$ROOT_DISK"
            echo "grub-pc grub-pc/install_devices multiselect /dev/$ROOT_DISK" | debconf-set-selections
        fi
    fi
fi

# Old images hold redis-server, which would keep it on the old release's version
apt-mark unhold redis-server || true

# Download every package before installing any, so a missing package or a network problem can't stop
# the upgrade halfway. Releases past their support end move to archive.debian.org, the security
# updates first (security.debian.org can keep listing packages it no longer serves), so try the
# archive when the downloads fail.
apt-get $APT_OPTIONS -y -f install || fail "Fixing broken packages failed"
DOWNLOADED=0
for MIRRORS in "http://deb.debian.org/debian http://security.debian.org/debian-security" \
               "http://deb.debian.org/debian http://archive.debian.org/debian-security" \
               "http://archive.debian.org/debian http://archive.debian.org/debian-security"; do
    write_debian_sources $MIRRORS
    cat /etc/apt/sources.list /etc/apt/sources.list.d/*.list
    # A failing third-party source doesn't stop the upgrade (apt_get_update records its errors)
    apt_get_update $APT_OPTIONS
    if apt-get $APT_OPTIONS -y --download-only full-upgrade && \
       { [ -z "$EXTRA_PACKAGES" ] || apt-get $APT_OPTIONS -y --download-only install $EXTRA_PACKAGES; }; then
        DOWNLOADED=1
        break
    fi
    echo "Downloading the packages failed with these sources, trying the next ones"
done
[ $DOWNLOADED = 1 ] || fail "The packages for Debian $TARGET could not be downloaded"

# Upgrade dpkg first: some of the new release's packages (Raspberry Pi's, for 12) are compressed with
# zstd, which the old dpkg can't unpack
apt-get $APT_OPTIONS -y install dpkg || fail "Upgrading dpkg failed"

# Upgrade in two steps, as the Debian release notes recommend
apt-get $APT_OPTIONS -y upgrade --without-new-pkgs || fail "apt-get upgrade failed"
apt-get $APT_OPTIONS -y full-upgrade || fail "apt-get full-upgrade failed"

NEW_VERSION=$(cut -d. -f1 /etc/debian_version)
if [ "$NEW_VERSION" != "$TARGET_VERSION" ]; then
    fail "The OS reports Debian $(cat /etc/debian_version) after the upgrade, not $TARGET_VERSION"
fi

if [ $RPI_BOOT_CONVERT = 1 ]; then
    install_rpi_kernel
    install_rpi_utils
fi

if [ $IS_X86 = 1 ]; then
    apt-mark hold 'grub*' || true
fi
apt-get $APT_OPTIONS clean || true
rm -rf $APT_ARCHIVES

# Make MyNode reinstall what was built or installed for the old release, like after flashing a new
# image: rebuild its Python, and clear the version records of installed apps (the install_* markers
# that say which apps are installed are kept). The data drive itself is not changed.
touch $PYTHON_REBUILD_FILE
find /home/bitcoin/.mynode /mnt/hdd/mynode/settings -maxdepth 1 -type f -name '*_version' -delete

# Settings reports the MyNode upgrade as failed until the post upgrade script finishes, so an
# interrupted run (power loss, a crash) is retried from there like an interrupted MyNode upgrade.
# Set before the target is removed, so one of the two is always left behind.
touch $UPGRADE_ERROR_FILE
# MyNode's post upgrade script reads the Debian release when it starts, so it sets up the new one
rm -f $TARGET_FILE
set +e
POST_UPGRADE_OK=0
for i in 1 2 3; do
    /bin/bash /usr/bin/mynode_post_upgrade.sh
    if [ $? -eq 0 ]; then
        POST_UPGRADE_OK=1
        break
    fi
    echo "Post upgrade script failed (attempt $i)"
    sleep 10
done
# When it failed, the OS upgrade itself still finished, so reboot anyway. Settings shows the MyNode
# upgrade error.
if [ $POST_UPGRADE_OK = 1 ] && [ ! -f $UPGRADE_INCOMPLETE_FILE ]; then
    rm -f $UPGRADE_ERROR_FILE
fi

if [ $RPI_BOOT_CONVERT = 1 ]; then
    remove_old_rpi_kernel
    # Don't reboot unless the device will boot the new kernel
    check_rpi_boot_files || fail "The boot partition is not ready for the new kernel, not rebooting"
fi

echo "OS upgraded to Debian $TARGET_VERSION ($TARGET). Rebooting."
chown -R admin:admin $LOG_DIR
sync
/usr/bin/mynode_stop_critical_services.sh
reboot
