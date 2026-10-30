#!/bin/bash

# Setup Initial LND Node Name
if [ ! -f /mnt/hdd/mynode/settings/.lndalias ]; then
    echo "mynodebtc.com [MyNode]" > /mnt/hdd/mynode/settings/.lndalias
fi

# LiT makes its self-signed TLS certificate only when there is none (valid about 14 months) and
# never renews it. Remove one expiring within 60 days, so LiT makes a new one when it starts.
LIT_TLS_CERT=/mnt/hdd/mynode/lit/tls.cert
if [ -f $LIT_TLS_CERT ] && ! openssl x509 -checkend 5184000 -noout -in $LIT_TLS_CERT > /dev/null 2>&1; then
    rm -f $LIT_TLS_CERT /mnt/hdd/mynode/lit/tls.key
fi

# Generate Lightning Terminal Config
if [ -f /mnt/hdd/mynode/settings/lit_custom.conf ]; then
    # Use Custom Config
    cp -f /mnt/hdd/mynode/settings/lit_custom.conf /mnt/hdd/mynode/lit/lit.conf
else
    # Generate a default config
    cp -f /usr/share/mynode/lit.conf /mnt/hdd/mynode/lit/lit.conf

    # Adjust Mainnet/Testnet
    if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
        sed -i "s/mainnet/testnet/g" /mnt/hdd/mynode/lit/lit.conf
    fi
fi

# LiT listens on 127.0.0.1 only, custom config or not; nginx serves it on 8443 behind the MyNode login
sed -i -e '/^[[:space:]]*httpslisten[[:space:]]*=/d' -e '/^[[:space:]]*insecure-httplisten[[:space:]]*=/d' /mnt/hdd/mynode/lit/lit.conf
sed -i '1i httpslisten=127.0.0.1:8444' /mnt/hdd/mynode/lit/lit.conf

# Faraday reads Bitcoin Core over RPC with the MyNode RPC password. It goes to sed on stdin with
# tracing off (startup sources this script), so it stays out of command lines and logs.
case $- in *x*) LIT_CONFIG_XTRACE=1 ;; *) LIT_CONFIG_XTRACE=0 ;; esac
set +x
if [ -s /mnt/hdd/mynode/settings/.btcrpcpw ]; then
    printf 's/^faraday.bitcoin.password=.*/faraday.bitcoin.password=%s/\n' "$(cat /mnt/hdd/mynode/settings/.btcrpcpw)" | \
        sed -i -f - /mnt/hdd/mynode/lit/lit.conf
fi
if [ "$LIT_CONFIG_XTRACE" = "1" ]; then
    set -x
fi


chown bitcoin:bitcoin /mnt/hdd/mynode/lit/lit.conf
chmod 600 /mnt/hdd/mynode/lit/lit.conf
