#!/bin/bash

# Main variables
OUTPUT_DIR="/home/bitcoin/.mynode/electrs"
domain=myNode.local
commonname=myNode.local

mkdir -p $OUTPUT_DIR

if [ -f $OUTPUT_DIR/$domain.pem ]; then
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
 
# Create the request
echo "Creating CSR"
openssl req -new -key $OUTPUT_DIR/$domain.key -out $OUTPUT_DIR/$domain.csr -passin pass:$password \
    -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email"

# Create Certificate
echo "Creating Certificate"
openssl x509 -req -days 99999 -in $OUTPUT_DIR/$domain.csr -signkey $OUTPUT_DIR/$domain.key -out $OUTPUT_DIR/$domain.crt

echo "Creating PEM"
cat $OUTPUT_DIR/$domain.key > $OUTPUT_DIR/$domain.pem
echo "" >> $OUTPUT_DIR/$domain.pem
cat $OUTPUT_DIR/$domain.crt >> $OUTPUT_DIR/$domain.pem
 