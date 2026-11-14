#!/bin/bash

source /usr/share/mynode/mynode_config.sh

NETWORK=mainnet
if [ -f $IS_TESTNET_ENABLED_FILE ]; then
    NETWORK=testnet
fi

# Loop and Pool have their own certificate and macaroon, in folders only the bitcoin user can open.
# Admin gets copies of those two files, as for LND, so the loop and pool commands work for admin.
copy_app_files_for_admin() {
    for app in loop pool; do
        src="/mnt/hdd/mynode/$app/$NETWORK"
        dst="/home/admin/.$app/$NETWORK"
        # Older versions linked admin's folder to the app's own
        if [ "$(readlink /home/admin/.$app)" = "/mnt/hdd/mynode/$app" ]; then
            rm -f /home/admin/.$app
        fi
        if [ -L /home/admin/.$app ] || [ ! -f "$src/tls.cert" ]; then
            continue
        fi
        install -d -o admin -g admin -m 700 /home/admin/.$app "$dst"
        for f in "$src/tls.cert" "$src/$app.macaroon"; do
            if [ -f "$f" ]; then
                install -o admin -g admin -m 600 "$f" "$dst/"
            fi
        done
    done
}

# What to watch for new or changed Loop and Pool files: the files once they exist, otherwise the
# nearest folder they will appear in (each app's database sits beside them and changes constantly)
app_watch_paths() {
    for app in loop pool; do
        src="/mnt/hdd/mynode/$app/$NETWORK"
        if [ -f "$src/$app.macaroon" ] && [ -f "$src/tls.cert" ]; then
            echo "$src/$app.macaroon" "$src/tls.cert"
        elif [ -d "$src" ]; then
            echo "$src"
        elif [ -d "/mnt/hdd/mynode/$app" ]; then
            echo "/mnt/hdd/mynode/$app"
        fi
    done
}

mkdir -p /home/admin/.lnd/
mkdir -p /home/admin/.lnd/data/chain/bitcoin/$NETWORK/
chown -R admin:admin /home/admin/.lnd/

echo "Waiting on lnd files..."
while [ ! -f $LND_TLS_CERT_FILE ]; do
    sleep 1m
done
# Copy cert so we can interact with LND even if wallet has not been created
cp -f $LND_TLS_CERT_FILE /home/admin/.lnd/
chown -R admin:admin /home/admin/.lnd/
while [ ! -f $LND_ADMIN_MACAROON_FILE ]; do
    sleep 1m
done
echo "LND files found!"

while true; do
    # Make sure lnd path exists for admin user
    mkdir -p /home/admin/.lnd/
    mkdir -p /home/admin/.lnd/data/chain/bitcoin/$NETWORK/
    chown -R admin:admin /home/admin/.lnd/

    # Copy LND files to admin folder
    cp -f $LND_TLS_CERT_FILE /home/admin/.lnd/
    cp -f /mnt/hdd/mynode/lnd/data/chain/bitcoin/$NETWORK/*.macaroon /home/admin/.lnd/data/chain/bitcoin/$NETWORK/
    chown -R admin:admin /home/admin/.lnd/
    copy_app_files_for_admin
    echo "Updated admin copy of LND, Loop and Pool files!"

    # Wait for changes. The timeout picks up Loop or Pool when either is installed later.
    inotifywait -t 3600 -e modify -e create -e delete -e moved_to -e delete_self -e move_self $LND_TLS_CERT_FILE /mnt/hdd/mynode/lnd/data/chain/bitcoin/$NETWORK/*.macaroon $(app_watch_paths)
    # Let a file that was just created be written in full before it is copied
    sleep 2
done

# Should never exit
exit 99