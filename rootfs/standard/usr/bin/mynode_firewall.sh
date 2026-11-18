#!/bin/bash

set -e
set -x

if ! command -v ufw > /dev/null; then
    echo "ERROR: ufw is not installed - the firewall is not running"
    exit 1
fi

# Make sure we are using legacy iptables
update-alternatives --set iptables /usr/sbin/iptables-legacy || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true

# Drop TCP packets with IPv4 options, which normal traffic doesn't use. The raw table also sees
# traffic to Docker containers, and ufw leaves it alone, so the rule stays through a ufw reload.
IP_OPTIONS_RULE=(PREROUTING -p tcp -m u32 --u32 "0>>24&0xF=6:15" -j DROP)
iptables -w -t raw -C "${IP_OPTIONS_RULE[@]}" || iptables -w -t raw -I "${IP_OPTIONS_RULE[@]}" || true

# ufw can lose rules when two ufw commands change them at the same time, so MyNode's firewall
# changes take this lock and run one at a time ("mynode-manage-apps openports" takes it itself)
exec 9> /run/mynode_firewall.lock
flock -x 9

# Add default rules
ufw default deny incoming
ufw default allow outgoing

# Add firewall rules
# Service ports are opened by "mynode-manage-apps openports" below: from the local network only,
# or from anywhere for the services selected in Settings (see /var/pynode/firewall_info.py)
ufw allow from 10.0.0.0/8 port 1900 to any      comment 'allow UPnP from router'
ufw allow from 192.168.0.0/16 port 1900 to any  comment 'allow UPnP from router'
ufw allow from 172.16.0.0/12 port 1900 to any   comment 'allow UPnP from router'
ufw allow from 172.17.0.0/16 to any port 28332 comment 'allow Dojo zmqrawblock'
ufw allow from 172.28.0.0/16 to any port 28332 comment 'allow Dojo zmqrawblock'
ufw allow from 172.17.0.0/16 to any port 28333 comment 'allow Dojo zmqrawtx'
ufw allow from 172.28.0.0/16 to any port 28333 comment 'allow Dojo zmqrawtx'
ufw allow from 172.17.0.0/16 to any port 28334 comment 'allow Dojo zmqhashblock'
ufw allow from 172.28.0.0/16 to any port 28334 comment 'allow Dojo zmqhashblock'
# WeTTY is reached through nginx on 2225
ufw --force delete allow 2224 || true
# The JoinMarket API is used by Jam, which runs in Docker; localhost is allowed below
ufw --force delete allow 27183 || true
ufw --force delete allow 28183 || true
ufw --force delete allow 28283 || true
ufw allow from 172.17.0.0/16 to any port 27183 comment 'allow JoinMarket API (Jam)'
ufw allow from 172.17.0.0/16 to any port 28183 comment 'allow JoinMarket API (Jam)'
ufw allow from 172.17.0.0/16 to any port 28283 comment 'allow JoinMarket API (Jam)'
ufw allow from 127.0.0.1 comment 'allow from localhost'
#ufw allow from ::1 comment 'allow from localhost'

# Open service and app ports, and remove rules from earlier versions
flock -u 9
mynode-manage-apps openports
flock -x 9

# Enable UFW
ufw --force enable

# Make sure ufw is enabled at boot
systemctl enable ufw

# Check UFW status
ufw status
flock -u 9

# Allow all local traffic. The setting is on the data drive, which mounts after this service starts,
# so wait for it. The rules from the last boot stay in place until then.
while [ ! -f /mnt/hdd/.mynode ]; do
    sleep 10s
done
flock -x 9
if [ -f /mnt/hdd/mynode/settings/local_traffic_allowed ]; then
    ufw allow from 10.0.0.0/8
    ufw allow from 192.168.0.0/16
    ufw allow from 172.16.0.0/12
else
    ufw delete allow from 10.0.0.0/8
    ufw delete allow from 192.168.0.0/16
    ufw delete allow from 172.16.0.0/12
fi
flock -u 9

# Reload firewall after some time to reset (fixes VPN)
sleep 120s
flock -x 9
ufw reload
flock -u 9

# We don't really want to exit
sleep 999d
exit 0
