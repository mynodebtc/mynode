#!/bin/bash

set -e
set -x

# Make sure we are using legacy iptables
update-alternatives --set iptables /usr/sbin/iptables-legacy || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true

# Add default rules
ufw default deny incoming
ufw default allow outgoing

# Add firewall rules
ufw allow 22    comment 'allow SSH'
ufw allow 80    comment 'allow WWW'
ufw allow 443   comment 'allow Secure WWW'
ufw allow 1900  comment 'allow SSDP for UPnP discovery'
ufw allow 10009 comment 'allow Lightning gRPC'
ufw allow 10080 comment 'allow Lightning REST RPC'
ufw allow 9735  comment 'allow Lightning'
ufw allow 8332  comment 'allow Bitcoin RPC - filtered by rpcallowip'
ufw allow 8333  comment 'allow Bitcoin mainnet'
ufw allow 18333 comment 'allow Bitcoin testnet'
ufw allow from 172.17.0.0/16 to any port 28332 comment 'allow Dojo zmqrawblock'
ufw allow from 172.28.0.0/16 to any port 28332 comment 'allow Dojo zmqrawblock'
ufw allow from 172.17.0.0/16 to any port 28333 comment 'allow Dojo zmqrawtx'
ufw allow from 172.28.0.0/16 to any port 28333 comment 'allow Dojo zmqrawtx'
ufw allow from 172.17.0.0/16 to any port 28334 comment 'allow Dojo zmqhashblock'
ufw allow from 172.28.0.0/16 to any port 28334 comment 'allow Dojo zmqhashblock'
ufw allow 8334  comment 'allow corsproxy for btc rpc'
ufw allow 2222  comment 'allow WebSSH2'
ufw allow 3000  comment 'allow LndHub'
ufw allow 3002  comment 'allow BTC RPC Explorer'
#ufw allow 3004  comment 'allow LND Admin'
ufw allow 3010  comment 'allow RTL'
ufw allow 3011  comment 'allow RTL HTTPS'
ufw allow 3020  comment 'allow Caravan'
ufw allow 3030  comment 'allow Thunderhub'
ufw allow 3031  comment 'allow Thunderhub HTTPS'
ufw allow 4080  comment 'allow Mempool'
ufw allow 5000  comment 'allow LNBits'
ufw allow 5001  comment 'allow LNBits HTTPS'
ufw allow 5353  comment 'allow Avahi'
ufw allow 8899  comment 'allow Whirlpool'
ufw allow 50001 comment 'allow Electrum Server'
ufw allow 50002 comment 'allow Electrum Server'
ufw allow 56881 comment 'allow myNode QuickSync'
ufw allow 51413 comment 'allow myNode QuickSync'
ufw allow 6771  comment 'allow myNode QuickSync (LPD)'
ufw allow 19999 comment 'allow Netdata'
ufw allow 25441 comment 'allow Specter Desktop'
ufw allow 49392 comment 'allow BTCPay Server-direct'
ufw allow 51194 comment 'allow VPN'
ufw allow 61208 comment 'allow Glances'
ufw allow from 127.0.0.1 comment 'allow from localhost'
#ufw allow from ::1 comment 'allow from localhost'

# Enable UFW
ufw --force enable

# Make sure ufw is enabled at boot
systemctl enable ufw

# Check UFW status
ufw status

# Reload firewall after some time to reset (fixes VPN)
sleep 120s
ufw reload

# We don't really want to exit
sleep 999d
exit 0
