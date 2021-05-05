#!/bin/bash

set -x
set -e

# Main variables
OUTPUT_DIR_BASE="/home/bitcoin/.mynode"
HDD_DIR_BASE="/mnt/hdd/mynode/settings"
mkdir -p $OUTPUT_DIR_BASE
mkdir -p $HDD_DIR_BASE

OUTPUT_DIR="${OUTPUT_DIR_BASE}/electrs"
HDD_DIR="${HDD_DIR_BASE}/electrs"
DAYS=10000

mkdir -p $OUTPUT_DIR
mkdir -p $HDD_DIR
domain=myNode.local
commonname=myNode.local

LOCAL_IP_ADDR=$(hostname -I | head -n 1 | cut -d' ' -f1)
TOR="electrstor.onion"
if [ -f /var/lib/tor/mynode_electrs/hostname ]; then
    TOR=$(cat /var/lib/tor/mynode_electrs/hostname)
fi

# Check for files on HDD and move to SD
if [ ! -f $OUTPUT_DIR/$domain.pem ] && [ -f $HDD_DIR/$domain.pem ]; then
    cp -f $HDD_DIR/* $OUTPUT_DIR/
fi

if [ -f $OUTPUT_DIR/$domain.pem ]; then
    # Verify files are stored on HDD
    cp -f $OUTPUT_DIR/* $HDD_DIR/

    exit 0
fi
 
# Change to your company details
country=US
state=myNode
locality=myNode
organization=myNode
organizationalunit=myNode
email=satoshi.nakamoto@example.com

# Create Certificate
echo "Creating Certificate"
cat > /tmp/cert_req.conf <<DELIM
[req]
prompt             = no
default_bits       = 2048
default_keyfile    = localhost.key
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_ca
[req_distinguished_name]
C=$country
ST=$state
L=$locality
O=$organization
#OU=$organizationalunit
CN=${commonname}
#emailAddress=$email
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

openssl req -x509 -nodes -days $DAYS -newkey rsa:2048 -keyout $OUTPUT_DIR/$domain.key -out $OUTPUT_DIR/$domain.crt -config /tmp/cert_req.conf

echo "Creating PEM"
cat $OUTPUT_DIR/$domain.key > $OUTPUT_DIR/$domain.pem
echo "" >> $OUTPUT_DIR/$domain.pem
cat $OUTPUT_DIR/$domain.crt >> $OUTPUT_DIR/$domain.pem

# Put copy of files of HDD
cp -f $OUTPUT_DIR/* $HDD_DIR/