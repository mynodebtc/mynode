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
if [ ! -z "$1" ]; then
    OUTPUT_DIR="${OUTPUT_DIR_BASE}/$1"
    HDD_DIR="${HDD_DIR_BASE}/$1"
fi
DAYS=99999
if [ ! -z "$2" ]; then
    DAYS=$2
fi

mkdir -p $OUTPUT_DIR
mkdir -p $HDD_DIR
domain=myNode.local
commonname=myNode.local

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
password=dummypassword
 
# Generate a key
echo "Creating key"
openssl genrsa -des3 -passout pass:$password -out $OUTPUT_DIR/$domain.key 2048
 
# Remove passphrase from the key
echo "Removing passphrase from key"
openssl rsa -in $OUTPUT_DIR/$domain.key -passin pass:$password -out $OUTPUT_DIR/$domain.key
 
# Create Certificate
echo "Creating Certificate"
cat > /tmp/cert_req.conf <<DELIM
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
utf8 = yes
[req_distinguished_name]
C=$country
ST=$state
L=$locality
O=$organization
OU=$organizationalunit
CN=${commonname}
emailAddress=$email
[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = $domain
DNS.2 = www.$domain
DNS.3 = localhost
DNS.4 = localhost.localdomain
DELIM

openssl req -x509 -nodes -days 730 -key $OUTPUT_DIR/$domain.key -out $OUTPUT_DIR/$domain.crt -config /tmp/cert_req.conf -extensions 'v3_req'

echo "Creating PEM"
cat $OUTPUT_DIR/$domain.key > $OUTPUT_DIR/$domain.pem
echo "" >> $OUTPUT_DIR/$domain.pem
cat $OUTPUT_DIR/$domain.crt >> $OUTPUT_DIR/$domain.pem

# Put copy of files of HDD
cp -f $OUTPUT_DIR/* $HDD_DIR/