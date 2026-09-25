#!/bin/bash

# Makes the certificate for the Electrum server's TLS port. It is self-signed and long lived on
# purpose: Electrum wallets pin it, so once made it is kept, and the copy on the drive wins.

set -x
set -e

# Main variables
OUTPUT_DIR_BASE="/home/bitcoin/.mynode"
HDD_DIR_BASE="/mnt/hdd/mynode/settings"
OUTPUT_DIR="${OUTPUT_DIR_BASE}/electrs"
HDD_DIR="${HDD_DIR_BASE}/electrs"
DAYS=10000

# nginx, startup and tls_proxy (as bitcoin) all run this. The lock is taken on this script, which
# every caller can open.
exec 9<"$0"
flock 9

# Without the drive, only the OS drive copy is made. Writing under /mnt/hdd would put the files
# on the OS drive, hidden once the drive is mounted over them.
DRIVE_MOUNTED=0
if [ -f /mnt/hdd/.mynode ]; then
    DRIVE_MOUNTED=1
fi

mkdir -p $OUTPUT_DIR
if [ $DRIVE_MOUNTED = 1 ]; then
    mkdir -p $HDD_DIR
fi
domain=mynode.local

# Earlier versions named the files myNode.local. Rename them instead of making a new certificate,
# since wallets pin it. They are the certificate this device has been serving, so they replace any
# files that already have the new name, which can only be leftovers from a development build.
rename_old_files() {
    local ext
    if [ -f $1/myNode.local.crt ] && [ -f $1/myNode.local.key ] && [ -f $1/myNode.local.pem ]; then
        for ext in crt key pem; do
            mv -f $1/myNode.local.$ext $1/$domain.$ext
        done
    fi
}
rename_old_files $OUTPUT_DIR
if [ $DRIVE_MOUNTED = 1 ]; then
    rename_old_files $HDD_DIR
fi

has_cert() {
    [ -f $1/$domain.crt ] && [ -f $1/$domain.key ] && [ -f $1/$domain.pem ]
}

# The drive's copy is the one wallets have pinned, so the OS drive copy always matches it. This also
# replaces a temporary certificate made before the drive was mounted.
if [ $DRIVE_MOUNTED = 1 ] && has_cert $HDD_DIR; then
    if ! cmp -s $HDD_DIR/$domain.pem $OUTPUT_DIR/$domain.pem; then
        cp -f $HDD_DIR/$domain.crt $HDD_DIR/$domain.key $HDD_DIR/$domain.pem $OUTPUT_DIR/
    fi
fi

if has_cert $OUTPUT_DIR; then
    # Verify files are stored on HDD
    if [ $DRIVE_MOUNTED = 1 ] && ! has_cert $HDD_DIR; then
        cp -f $OUTPUT_DIR/$domain.crt $OUTPUT_DIR/$domain.key $OUTPUT_DIR/$domain.pem $HDD_DIR/
    fi
    exit 0
fi

LOCAL_IP_ADDR=$(hostname -I | head -n 1 | cut -d' ' -f1)
TOR="electrstor.onion"
if [ -f /var/lib/tor/mynode_electrs/hostname ]; then
    TOR=$(cat /var/lib/tor/mynode_electrs/hostname)
fi

# Change to your company details
country=US
state=MyNode
locality=MyNode
organization=MyNode

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Create Certificate
echo "Creating Certificate"
cat > $TMP_DIR/cert_req_electrs.conf <<DELIM
[req]
prompt             = no
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_ca
[req_distinguished_name]
C=$country
ST=$state
L=$locality
O=$organization
CN=$domain
[req_ext]
subjectAltName = @alt_names
[v3_ca]
subjectAltName = @alt_names
[alt_names]
DNS.1 = $domain
DNS.2 = www.$domain
DNS.3 = localhost
DNS.4 = 127.0.0.1
DNS.5 = $LOCAL_IP_ADDR
DNS.6 = $TOR
DELIM

openssl req -x509 -nodes -days $DAYS -newkey rsa:2048 -keyout $TMP_DIR/key -out $TMP_DIR/crt -config $TMP_DIR/cert_req_electrs.conf

echo "Creating PEM"
cat $TMP_DIR/key > $TMP_DIR/pem
echo "" >> $TMP_DIR/pem
cat $TMP_DIR/crt >> $TMP_DIR/pem

# Move the new files into place only once all of them exist. tls_proxy reads them as bitcoin.
dirs=$OUTPUT_DIR
if [ $DRIVE_MOUNTED = 1 ]; then
    dirs="$dirs $HDD_DIR"
fi
for dir in $dirs; do
    install -m 600 -o bitcoin -g bitcoin $TMP_DIR/key $dir/$domain.key.new
    install -m 644 -o bitcoin -g bitcoin $TMP_DIR/crt $dir/$domain.crt.new
    install -m 600 -o bitcoin -g bitcoin $TMP_DIR/pem $dir/$domain.pem.new
    mv -f $dir/$domain.key.new $dir/$domain.key
    mv -f $dir/$domain.crt.new $dir/$domain.crt
    mv -f $dir/$domain.pem.new $dir/$domain.pem
done
