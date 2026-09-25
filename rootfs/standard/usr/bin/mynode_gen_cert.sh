#!/bin/bash

# Issues the HTTPS certificate for a subfolder of /home/bitcoin/.mynode, signed by the device's own
# certificate authority. A user can install the CA once and trust every certificate it issues, so
# the certificate itself stays short lived and is reissued whenever it nears expiry or the device's
# names or IP address change.
#
# Usage: mynode_gen_cert.sh <subfolder> [days]

set -x
set -e

# Main variables
OUTPUT_DIR_BASE="/home/bitcoin/.mynode"
HDD_DIR_BASE="/mnt/hdd/mynode/settings"

# Without the drive, only the OS drive copy is made. Writing under /mnt/hdd would put the files
# on the OS drive, hidden once the drive is mounted over them.
DRIVE_MOUNTED=0
if [ -f /mnt/hdd/.mynode ]; then
    DRIVE_MOUNTED=1
fi

mkdir -p $OUTPUT_DIR_BASE
if [ $DRIVE_MOUNTED = 1 ]; then
    mkdir -p $HDD_DIR_BASE
fi

OUTPUT_DIR="UNKNOWN"
HDD_DIR="UNKNOWN"
if [ -z "$1" ]; then
    echo "Need certificate subfolder! Exiting."
    exit 1
fi
OUTPUT_DIR="${OUTPUT_DIR_BASE}/$1"
HDD_DIR="${HDD_DIR_BASE}/$1"

# nginx runs this each time it starts, and startup and the settings page run it too. The lock is
# taken on this script, which every caller can open.
exec 9<"$0"
flock 9

# Apple devices do not trust certificates valid for more than 825 days
DAYS=820
if [ ! -z "$2" ]; then
    DAYS=$2
fi
# Reissue certificates that expire within this many seconds (30 days)
RENEW_SECONDS=2592000

mkdir -p $OUTPUT_DIR
if [ $DRIVE_MOUNTED = 1 ]; then
    mkdir -p $HDD_DIR
fi
# Changing the domain changes the file names below, so every device issues a new certificate
domain=mynode.local

# The CA key must stay readable by root only. /home/bitcoin/.mynode and /mnt/hdd/mynode/settings
# are both chowned to bitcoin recursively, so it lives in its own folder on the drive.
CA_DIR="/mnt/hdd/mynode/https_ca"
CA_KEY="$CA_DIR/mynode_ca.key"
CA_CRT="$CA_DIR/mynode_ca.crt"
CA_DAYS=3650

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# The CA only permits these networks and names (see generate_ca). Certificates naming anything
# else would be rejected by browsers, so leave out an IP address outside them.
is_permitted_ip() {
    case "$1" in
        10.*|127.*|192.168.*) return 0 ;;
        172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
    esac
    return 1
}

LOCAL_IP_ADDR=$(hostname -I | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
if ! is_permitted_ip "$LOCAL_IP_ADDR"; then
    LOCAL_IP_ADDR=""
fi

# Names for the certificate
LABEL='[a-z0-9]([a-z0-9-]*[a-z0-9])?'
NAMES="$domain www.$domain localhost"
HOST_NAME=$(hostname -s | tr 'A-Z' 'a-z')
if echo "$HOST_NAME" | grep -qxE "$LABEL"; then
    NAMES="$NAMES $HOST_NAME.local"
fi
# The name Avahi publishes. With several devices on one network it renames all but the first to
# mynode-2.local, mynode-3.local and so on, while the hostname stays mynode.
AVAHI_NAME=$(busctl --timeout=2 call org.freedesktop.Avahi / org.freedesktop.Avahi.Server GetHostNameFqdn 2>/dev/null | sed -n 's/^s "\(.*\)"$/\1/p' | tr 'A-Z' 'a-z' || true)
if echo "$AVAHI_NAME" | grep -qxE "($LABEL\.)+local"; then
    NAMES="$NAMES $AVAHI_NAME"
fi
if [ -f /var/lib/tor/mynode/hostname ]; then
    TOR=$(cat /var/lib/tor/mynode/hostname)
    if echo "$TOR" | grep -qxE '[a-z2-7]{56}\.onion'; then
        NAMES="$NAMES $TOR"
    fi
fi
# Additional .local names, one per line
if [ -f $HDD_DIR/extra_names ]; then
    for name in $(tr 'A-Z' 'a-z' < $HDD_DIR/extra_names); do
        if echo "$name" | grep -qxE "($LABEL\.)+local"; then
            NAMES="$NAMES $name"
        fi
    done
fi
NAMES=$(echo $NAMES | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' ')

cert_matches_key() {
    [ "$(openssl x509 -in "$1" -noout -pubkey 2>/dev/null)" = "$(openssl pkey -in "$2" -pubout 2>/dev/null)" ]
}

ca_is_current() {
    [ -f $CA_KEY ] && [ -f $CA_CRT ] || return 1
    # Replacing the CA means users must trust the new one, so only do it when it is about to expire
    openssl x509 -in $CA_CRT -noout -checkend $RENEW_SECONDS >/dev/null 2>&1 || return 1
    cert_matches_key $CA_CRT $CA_KEY
}

generate_ca() {
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out $TMP_DIR/ca.key
    # The random suffix tells apart the CAs of two devices installed on the same computer
    cat > $TMP_DIR/ca.conf <<DELIM
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no
utf8 = yes
[req_distinguished_name]
O=MyNode
CN=MyNode Local CA $(openssl rand -hex 4)
[v3_ca]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
nameConstraints = critical, @name_constraints
[name_constraints]
permitted;DNS.1 = local
permitted;DNS.2 = localhost
permitted;DNS.3 = onion
permitted;IP.1 = 10.0.0.0/255.0.0.0
permitted;IP.2 = 172.16.0.0/255.240.0.0
permitted;IP.3 = 192.168.0.0/255.255.0.0
permitted;IP.4 = 127.0.0.0/255.0.0.0
DELIM
    openssl req -x509 -new -key $TMP_DIR/ca.key -config $TMP_DIR/ca.conf -days $CA_DAYS \
        -set_serial 0x$(openssl rand -hex 16) -out $TMP_DIR/ca.crt

    install -d -m 700 -o root -g root $CA_DIR
    install -m 600 -o root -g root $TMP_DIR/ca.key $CA_KEY.new
    install -m 644 -o root -g root $TMP_DIR/ca.crt $CA_CRT.new
    mv -f $CA_KEY.new $CA_KEY
    mv -f $CA_CRT.new $CA_CRT
}

leaf_is_current() {
    local crt=$OUTPUT_DIR/$domain.crt
    local key=$OUTPUT_DIR/$domain.key
    [ -f $crt ] && [ -f $key ] && [ -f $OUTPUT_DIR/$domain.pem ] || return 1
    openssl x509 -in $crt -noout -checkend $RENEW_SECONDS >/dev/null 2>&1 || return 1
    cert_matches_key $crt $key || return 1
    if [ "$CA_AVAILABLE" = "1" ]; then
        openssl verify -CAfile $CA_CRT -purpose sslserver $crt >/dev/null 2>&1 || return 1
    fi

    # Every current name and the IP address must be in the certificate. Parsed from -text because
    # -ext needs OpenSSL 3, and Debian 10 has 1.1.1.
    local san=$(openssl x509 -in $crt -noout -text 2>/dev/null | grep -A1 "X509v3 Subject Alternative Name" | tail -n 1 | tr ',' '\n' | sed 's/^ *//')
    local name
    for name in $NAMES; do
        echo "$san" | grep -qxF "DNS:$name" || return 1
    done
    if [ -n "$LOCAL_IP_ADDR" ]; then
        echo "$san" | grep -qxF "IP Address:$LOCAL_IP_ADDR" || return 1
    fi
    return 0
}

issue_leaf() {
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out $TMP_DIR/leaf.key

    cat > $TMP_DIR/leaf.conf <<DELIM
[req]
distinguished_name = req_distinguished_name
prompt = no
utf8 = yes
[req_distinguished_name]
O=MyNode
CN=$domain
[v3_leaf]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
subjectAltName = @alt_names
[alt_names]
DELIM
    local i=1
    local name
    for name in $NAMES; do
        echo "DNS.$i = $name" >> $TMP_DIR/leaf.conf
        i=$((i+1))
    done
    if [ -n "$LOCAL_IP_ADDR" ]; then
        echo "IP.1 = $LOCAL_IP_ADDR" >> $TMP_DIR/leaf.conf
    fi

    if [ "$CA_AVAILABLE" = "1" ]; then
        openssl req -new -key $TMP_DIR/leaf.key -config $TMP_DIR/leaf.conf -out $TMP_DIR/leaf.csr
        openssl x509 -req -in $TMP_DIR/leaf.csr -CA $CA_CRT -CAkey $CA_KEY \
            -set_serial 0x$(openssl rand -hex 16) -days $DAYS \
            -extfile $TMP_DIR/leaf.conf -extensions v3_leaf -out $TMP_DIR/leaf.crt
    else
        # No drive, so no CA. Sign it with its own key so nginx can still start; it is replaced
        # with one from the CA on the next run with the drive mounted.
        openssl req -x509 -new -key $TMP_DIR/leaf.key -config $TMP_DIR/leaf.conf -extensions v3_leaf \
            -set_serial 0x$(openssl rand -hex 16) -days $DAYS -out $TMP_DIR/leaf.crt
    fi

    cat $TMP_DIR/leaf.key > $TMP_DIR/leaf.pem
    echo "" >> $TMP_DIR/leaf.pem
    cat $TMP_DIR/leaf.crt >> $TMP_DIR/leaf.pem

    # Move the new files into place only once all of them exist, so a failure above leaves the
    # previous certificate in use
    local dirs=$OUTPUT_DIR
    if [ $DRIVE_MOUNTED = 1 ]; then
        dirs="$dirs $HDD_DIR"
    fi
    local dir
    for dir in $dirs; do
        install -m 600 $TMP_DIR/leaf.key $dir/$domain.key.new
        install -m 644 $TMP_DIR/leaf.crt $dir/$domain.crt.new
        install -m 600 $TMP_DIR/leaf.pem $dir/$domain.pem.new
        mv -f $dir/$domain.key.new $dir/$domain.key
        mv -f $dir/$domain.crt.new $dir/$domain.crt
        mv -f $dir/$domain.pem.new $dir/$domain.pem
    done
}

CA_AVAILABLE=0
if [ $DRIVE_MOUNTED = 1 ]; then
    if ! ca_is_current; then
        generate_ca
    fi
    CA_AVAILABLE=1

    # Use the copy on the drive when the OS drive has none, or has one that no longer passes, such
    # as the temporary certificate made before the drive was mounted
    if ! leaf_is_current && [ -f $HDD_DIR/$domain.pem ]; then
        cp -f $HDD_DIR/* $OUTPUT_DIR/
    fi
else
    # Without the drive there is no CA, so the only job is letting nginx start. Keep any certificate
    # that matches its key, even an out of date one, since it may be signed by the CA and trusted.
    # It is renewed once the drive is mounted.
    if [ -f $OUTPUT_DIR/$domain.crt ] && [ -f $OUTPUT_DIR/$domain.key ] && cert_matches_key $OUTPUT_DIR/$domain.crt $OUTPUT_DIR/$domain.key; then
        echo "Drive not mounted, keeping the existing certificate."
        exit 0
    fi
fi

if leaf_is_current; then
    # Verify files are stored on HDD
    if [ $DRIVE_MOUNTED = 1 ] && [ ! -f $HDD_DIR/$domain.pem ]; then
        cp -f $OUTPUT_DIR/* $HDD_DIR/
    fi
    echo "Certificate is current."
    exit 0
fi

echo "Creating certificate"
issue_leaf
