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

function has_app_python() {
    [ "$IS_64_BIT" = "1" ] && mynode-uv python find $APP_PYTHON_MINOR_VERSION > /dev/null 2>&1
}

function venv_uses_app_python() {
    grep -q "^home = /usr/local/lib/mynode/python/" "$1/pyvenv.cfg" 2>/dev/null
}

function build_root_venv() {
    # Build the venv /usr/local/lib/mynode/venv/<name> on the Python for apps, from
    # /usr/share/mynode/venvs/<name>.lock (and <name>.pth when there is one), and check it by
    # running the Python in $2. Root-owned, for tools that run as root or admin.
    # Each build gets its own folder, named after its files, and venv/<name> is a link switched to
    # it only after the check passes: a failed build changes nothing, and running processes keep
    # their files. remove_unused_root_venvs removes the old folders at startup.
    local name="$1"
    local root=/usr/local/lib/mynode/venv
    local lock="/usr/share/mynode/venvs/$name.lock"
    local pth="/usr/share/mynode/venvs/$name.pth"
    local hash=$(cat "$lock" "$pth" 2>/dev/null | sha256sum | cut -c1-12)
    local dir="$name-$hash-py$APP_PYTHON_MINOR_VERSION"
    local check="$2"
    if [ -f "$pth" ]; then
        check="$check; import sys; assert all(p in sys.path for p in open('$pth').read().split())"
    fi

    install -d -m 0755 -o root -g root $root
    if ! (cd / && "$root/$dir/bin/python" -I -c "$check") > /dev/null 2>&1; then
        rm -rf "$root/$dir"
        if ! mynode-uv venv --python $APP_PYTHON_MINOR_VERSION "$root/$dir" || \
           ! mynode-uv pip install --require-hashes --python "$root/$dir/bin/python" -r "$lock"; then
            rm -rf "$root/$dir"
            return 1
        fi
        if [ -f "$pth" ]; then
            cp "$pth" "$root/$dir/lib/python$APP_PYTHON_MINOR_VERSION/site-packages/"
        fi
        if ! (cd / && "$root/$dir/bin/python" -I -c "$check"); then
            echo "ERROR: The $name venv failed its check"
            rm -rf "$root/$dir"
            return 1
        fi
    fi

    # Venvs built before they had their own folders are real folders here
    if [ -d "$root/$name" ] && [ ! -L "$root/$name" ]; then
        rm -rf "$root/$name-legacy"
        mv -T "$root/$name" "$root/$name-legacy"
    fi
    ln -sfn "$dir" "$root/.$name.new"
    mv -T "$root/.$name.new" "$root/$name"
}

function build_www_venv() {
    # The venv for the web UI and MyNode's own scripts (see mynode-python)
    build_root_venv www "import flask, pam, bcrypt, qrcode, PIL, psutil, pyudev, inotify_simple, prometheus_client, bitcoinrpc, requests, socks; from systemd import journal"
}

function remove_unused_root_venvs() {
    # Remove the venv folders build_root_venv left behind, keeping the ones the links point at.
    # Run at startup, when nothing still runs from them.
    local root=/usr/local/lib/mynode/venv
    local link
    local dir
    for link in $root/*; do
        [ -L "$link" ] && [ -e "$link" ] || continue
        local name=$(basename "$link")
        local current=$(readlink "$link")
        for dir in "$link"-*; do
            [ -d "$dir" ] && [ ! -L "$dir" ] || continue
            [ "$(basename "$dir")" != "$current" ] || continue
            if [[ "$(basename "$dir")" =~ ^$name-([0-9a-f]{12}-py[0-9.]+|legacy)$ ]]; then
                rm -rf "$dir"
            fi
        done
    done
}

function remove_old_app_pythons() {
    # Remove other patch versions of the Python for apps, once APP_PYTHON_VERSION is installed.
    # Run at startup: running processes use the patch version they started with.
    local dir
    local ver
    ls -d /usr/local/lib/mynode/python/cpython-$APP_PYTHON_VERSION-linux-* > /dev/null 2>&1 || return 0
    for dir in /usr/local/lib/mynode/python/cpython-$APP_PYTHON_MINOR_VERSION.*-linux-*; do
        [ -d "$dir" ] || continue
        ver=$(basename $dir | cut -d- -f2)
        if [ "$ver" != "$APP_PYTHON_VERSION" ]; then
            mynode-uv python uninstall $ver || true
        fi
    done
}

function generate_app_password() {
    # Letters and digits only, so the password copies with a double-click
    /usr/bin/mynode-python -c 'import secrets, string; a = string.ascii_letters + string.digits; print("".join(secrets.choice(a) for i in range(24)))'
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