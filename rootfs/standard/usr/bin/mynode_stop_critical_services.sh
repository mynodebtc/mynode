#!/bin/bash

# Mark we are shutting down
touch /tmp/shutting_down


# Stop additional services
systemctl stop glances
systemctl stop lndhub
systemctl stop netdata
systemctl stop rtl
systemctl stop webssh2
systemctl stop whirlpool
systemctl stop dojo
systemctl stop btcpayserver
systemctl stop btc_rpc_explorer


# Manually stop services (backup)
/opt/mynode/dojo/docker/my-dojo/dojo.sh stop || true


# Stop core services
systemctl stop electrs
systemctl stop lnd
systemctl stop quicksync
systemctl stop bitcoind

sync
