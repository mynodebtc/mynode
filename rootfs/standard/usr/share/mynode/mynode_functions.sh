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

function is_service_enabled {
    systemctl is-enabled "$1" > /dev/null 2>&1
}

function skip_base_upgrades {
    if [ -f /tmp/skip_base_upgrades ]; then
        return 0
    fi
    return 1
}

function generate_app_password() {
    # Letters and digits only, so the password copies with a double-click
    /usr/local/bin/python3 -c 'import secrets, string; a = string.ascii_letters + string.digits; print("".join(secrets.choice(a) for i in range(24)))'
}

function has_app_password() {
    [ -s "/mnt/hdd/mynode/${1}/.app_password" ]
}

function save_app_default_password() {
    # Record the login password MyNode set for an app, so the app page can show it.
    # Stored in the app's storage folder, which is owned by the app's user.
    (umask 077; printf '%s\n' "$2" > "/mnt/hdd/mynode/${1}/.app_password")
    # When written as root, keep it readable by pre-start scripts that run as the app's user
    if [ "$(id -u)" = "0" ]; then
        chown --reference="/mnt/hdd/mynode/${1}" "/mnt/hdd/mynode/${1}/.app_password"
    fi
}

# Saved in place of the password once the user has set their own, so MyNode stops managing
# it. Must match APP_PASSWORD_USER_SET in application_info.py.
APP_PASSWORD_USER_SET="User configured (not managed by MyNode)"

function save_app_password_user_set() {
    save_app_default_password "$1" "$APP_PASSWORD_USER_SET"
}

function is_app_password_user_set() {
    [ "$(cat "/mnt/hdd/mynode/${1}/.app_password" 2>/dev/null)" = "$APP_PASSWORD_USER_SET" ]
}

function remove_docker_images_by_name() {
    local name="$1"
    local images

    # Capture matches safely; no-match should not be treated as an error.
    images="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep "$name" || true)"

    # Nothing to remove.
    [ -z "$images" ] && return 0

    # Remove all matched images.
    printf '%s\n' "$images" | xargs --no-run-if-empty docker rmi
}