#!/bin/bash

# push-local-upgrade.sh
# Dev PC side companion to mynode-local-upgrade.
#
# Connects to a MyNode device, determines its device type, rebuilds the rootfs
# for just that device type, copies the tarball from out/ over SCP, and runs
# mynode-local-upgrade on the device with the tarball path.
#
# Usage: scripts/push-local-upgrade.sh [OPTIONS] <DEVICE_IP> [SERVICE]
#
#   SERVICE is passed straight through to mynode-local-upgrade:
#     www            - reinit apps and restart the www service (web UI changes)
#     apps           - reinit apps only
#     files          - copy files, restart nothing
#     mempool        - restart mempool
#     docker_images  - restart docker_images
#     (omitted)      - full upgrade, runs post upgrade script and reboots

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

user="admin"
build=1
keep_tarball=0
device_type=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <DEVICE_IP> [SERVICE]

Options:
  -u, --user USER      SSH user on the device (default: admin)
  -n, --no-build       Skip the rebuild and push the existing tarball in out/
  -t, --type TYPE      Skip detection and use this device type (raspi4, raspi5,
                       debian, rockpro64, ...)
  -k, --keep           Leave the copied tarball on the device
  -h, --help           Show this help

Examples:
  $(basename "$0") 192.168.86.205 www
  $(basename "$0") -n 192.168.86.204 files   # push the existing build
  $(basename "$0") 192.168.86.205            # full upgrade + reboot
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -u|--user)  user="$2"; shift 2 ;;
        -t|--type)  device_type="$2"; shift 2 ;;
        -n|--no-build) build=0; shift ;;
        -k|--keep)  keep_tarball=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        -*)         echo "ERROR: Unknown option '$1'"; usage; exit 1 ;;
        *)          break ;;
    esac
done

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

device_ip="$1"
service="${2:-}"

if [ "$#" -gt 2 ]; then
    echo "ERROR: Too many arguments"
    usage
    exit 1
fi

ssh_target="${user}@${device_ip}"

# Check the device is reachable
echo -n "Connecting to ${ssh_target}... "
if ! ssh -o ConnectTimeout=10 -o BatchMode=no "${ssh_target}" true; then
    echo "ERROR: Unable to SSH to ${ssh_target}"
    exit 1
fi
echo "Done!"

# Determine the device type
if [ -z "${device_type}" ]; then
    echo -n "Determining device type... "
    device_type=$(ssh "${ssh_target}" \
        'source /usr/share/mynode/mynode_device_info.sh >/dev/null 2>&1; echo "${DEVICE_TYPE}"' \
        | tr -d '\r' | tail -1)
    if [ -z "${device_type}" ] || [ "${device_type}" = "unknown" ]; then
        echo "ERROR: Could not determine device type (got '${device_type}')"
        echo "       Use --type to specify it manually."
        exit 1
    fi
    echo "${device_type}"
else
    echo "Using device type: ${device_type}"
fi

# Rebuild the rootfs for this device type (skipped with --no-build)
if [ "${build}" -eq 1 ]; then
    echo "Building rootfs for ${device_type}..."
    (cd "${REPO_DIR}" && ./make_rootfs.sh "${device_type}")
fi

# Find the tarball for this device
tarball="${REPO_DIR}/out/mynode_rootfs_${device_type}.tar.gz"
if [ ! -f "${tarball}" ]; then
    echo "ERROR: ${tarball} not found!"
    echo "       Drop --no-build to build it, or run 'make rootfs DEVICES=\"${device_type}\"'."
    exit 1
fi

tarball_bytes=$(stat -f %z "${tarball}" 2>/dev/null || stat -c %s "${tarball}")
tarball_size=$(awk -v b="${tarball_bytes}" 'BEGIN{printf "%.0fMB", b/1048576}')
tarball_mtime=$(stat -f %m "${tarball}" 2>/dev/null || stat -c %Y "${tarball}")
tarball_age=$(( $(date +%s) - tarball_mtime ))
if   [ "${tarball_age}" -lt 120 ];   then age_str="${tarball_age}s ago"
elif [ "${tarball_age}" -lt 7200 ];  then age_str="$(( tarball_age / 60 ))m ago"
elif [ "${tarball_age}" -lt 172800 ]; then age_str="$(( tarball_age / 3600 ))h ago"
else age_str="$(( tarball_age / 86400 ))d ago"
fi
tarball_date=$(date -r "${tarball_mtime}" '+%Y-%m-%d %H:%M' 2>/dev/null \
    || date -d "@${tarball_mtime}" '+%Y-%m-%d %H:%M')
echo "Using $(basename "${tarball}") (${tarball_size}, built ${tarball_date}, ${age_str})"

# Copy the tarball to the device
remote_tarball="/tmp/mynode_rootfs_${device_type}.tar.gz"
echo "Copying rootfs to ${ssh_target}:${remote_tarball}..."
scp "${tarball}" "${ssh_target}:${remote_tarball}"

# Run the upgrade
echo ""
echo "Running mynode-local-upgrade on ${device_ip}..."
echo ""
set +e
ssh -t "${ssh_target}" "sudo /usr/bin/mynode-local-upgrade ${remote_tarball} ${service}"
upgrade_result=$?
set -e

if [ -z "${service}" ] && [ "${upgrade_result}" -ne 0 ]; then
    # A full upgrade reboots the device, which drops the SSH connection
    echo ""
    echo "Connection closed - the device is rebooting."
    exit 0
fi

if [ "${upgrade_result}" -ne 0 ]; then
    echo ""
    echo "ERROR: mynode-local-upgrade failed (exit ${upgrade_result})"
    exit "${upgrade_result}"
fi

# Clean up the copied tarball
if [ "${keep_tarball}" -eq 0 ]; then
    ssh "${ssh_target}" "sudo rm -f ${remote_tarball}" || true
fi

echo ""
echo "Done! Upgraded ${device_ip} (${device_type})"
