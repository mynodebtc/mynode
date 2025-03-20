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
ufw allow 2189  comment 'allow UPnP'
ufw allow from 10.0.0.0/8 port 1900 to any      comment 'allow UPnP from router'
ufw allow from 192.168.0.0/16 port 1900 to any  comment 'allow UPnP from router'
ufw allow from 172.16.0.0/12 port 1900 to any   comment 'allow UPnP from router'
ufw allow 9911  comment 'allow Lightning Watchtower'
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
ufw allow 8335  comment 'allow corsproxy for btc rpc (old)'
ufw allow 8336  comment 'allow nginx proxy for btc rpc 2'
ufw allow 8443  comment 'allow Lightning Terminal'
ufw allow 2222  comment 'allow WebSSH2'
ufw allow 2223  comment 'allow WebSSH2 HTTPS'
ufw allow 3000  comment 'allow LndHub'
ufw allow 3001  comment 'allow LndHub HTTPS'
ufw allow 3002  comment 'allow BTC RPC Explorer'
ufw allow 3003  comment 'allow BTC RPC Explorer HTTPS'
ufw allow 3010  comment 'allow RTL'
ufw allow 3011  comment 'allow RTL HTTPS'
ufw allow 3020  comment 'allow Caravan'
ufw allow 3021  comment 'allow Caravan HTTPS'
ufw allow 3030  comment 'allow Thunderhub'
ufw allow 3031  comment 'allow Thunderhub HTTPS'
ufw allow 3493  comment 'allow Network UPS Tools'
ufw allow 4080  comment 'allow Mempool'
ufw allow 4081  comment 'allow Mempool HTTPS'
ufw allow 5000  comment 'allow LNBits'
ufw allow 5001  comment 'allow LNBits HTTPS'
ufw allow 5010  comment 'allow Warden Terminal'
ufw allow 5011  comment 'allow Warden Terminal HTTPS'
ufw allow 5351  comment 'allow NAT-PMP'
ufw allow 5353  comment 'allow Avahi'
ufw allow 6001  comment 'allow Public App - LNBits'
ufw allow 6002  comment 'allow Public App - BTCPayServer'
ufw allow 6003  comment 'allow Public App - LNDHub'
#ufw allow 6004  comment 'allow Public App - Future'
#ufw allow 6005  comment 'allow Public App - Future'
#ufw allow 6006  comment 'allow Public App - Future'
#ufw allow 6007  comment 'allow Public App - Future'
#ufw allow 6008  comment 'allow Public App - Future'
#ufw allow 6009  comment 'allow Public App - Future'
#ufw allow 6010  comment 'allow Public App - Future'
ufw allow 8010:8019/tcp  comment 'allow USB Extras HTTP/HTTPS'
ufw allow 8899  comment 'allow Whirlpool'
ufw allow 9823  comment 'allow CKBunker'
ufw allow 9824  comment 'allow CKBunker HTTPS'
ufw allow 50001 comment 'allow Electrum Server'
ufw allow 50002 comment 'allow Electrum Server'
ufw allow 53001 comment 'allow Sphinx Relay'
ufw allow 56881 comment 'allow MyNode QuickSync'
ufw allow 51413 comment 'allow MyNode QuickSync'
ufw allow 6771  comment 'allow MyNode QuickSync (LPD)'
ufw allow 19999 comment 'allow Netdata'
ufw allow 20000 comment 'allow Netdata HTTPS'
ufw allow 25441 comment 'allow Specter Desktop'
ufw allow 49392 comment 'allow BTCPay Server-direct'
ufw allow 49393 comment 'allow BTCPay Server-direct HTTPS'
ufw allow 51194 comment 'allow VPN'
ufw allow 61208 comment 'allow Glances'
ufw allow 61209 comment 'allow Glances HTTPS'
ufw allow 62601 comment 'allow JoinMarket Orderbook'
ufw allow 62602 comment 'allow JoinMarket Orderbook HTTPS'
ufw allow 27183 comment 'allow JoinMarket API'
ufw allow 28183 comment 'allow JoinMarket API'
ufw allow 23334  comment 'allow DATUM stratum'
ufw allow 9740  comment 'allow phoenixd'
ufw allow 8080  comment 'allow albyHub'
ufw allow from 127.0.0.1 comment 'allow from localhost'
#ufw allow from ::1 comment 'allow from localhost'

# Allow all local traffic
if [ -f /mnt/hdd/mynode/settings/local_traffic_allowed ]; then
    ufw allow from 10.0.0.0/8
    ufw allow from 192.168.0.0/16
    ufw allow from 172.16.0.0/12
else
    ufw delete allow from 10.0.0.0/8
    ufw delete allow from 192.168.0.0/16
    ufw delete allow from 172.16.0.0/12
fi

# Open ports for additional apps
mynode-manage-apps openports

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
