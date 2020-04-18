#!/bin/bash

set -x
set -e

source /usr/share/mynode/mynode_config.sh

# replace Dojo bitcoind.conf.tpl with custom conf for MyNode
rm -rf /opt/mynode/dojo/docker/my-dojo/conf/docker-bitcoind.conf.tpl
touch /opt/mynode/dojo/docker/my-dojo/conf/docker-bitcoind.conf.tpl

RPC_PASS=$(cat /mnt/hdd/mynode/settings/.btcrpc_environment | cut -c 18- )

echo "
#########################################
# CONFIGURATION OF BITCOIND CONTAINER   #
#########################################
# User account used for rpc access to bitcoind Type: alphanumeric
BITCOIND_RPC_USER=mynode
# Password of user account used for rpc access to bitcoind Type:
# alphanumeric
BITCOIND_RPC_PASSWORD=$RPC_PASS
# Max number of connections to network peers Type: integer
BITCOIND_MAX_CONNECTIONS=16
# Mempool maximum size in MB Type: integer
BITCOIND_MAX_MEMPOOL=600
# Db cache size in MB Type: integer
BITCOIND_DB_CACHE=1024
# Number of threads to service RPC calls Type: integer
BITCOIND_RPC_THREADS=6
# Mempool expiry in hours Defines how long transactions stay in your local
# mempool before expiring Type: integer
BITCOIND_MEMPOOL_EXPIRY=72
# Min relay tx fee in BTC Type: numeric
BITCOIND_MIN_RELAY_TX_FEE=0.00001
#
# EXPERT SETTINGS
#
# EPHEMERAL ONION ADDRESS FOR BITCOIND THIS PARAMETER HAS NO EFFECT IF
# BITCOIND_INSTALL IS SET TO OFF
#
# Generate a new onion address for bitcoind when Dojo is launched
# Activation of this option is recommended for improved privacy. Values: on
# | off
BITCOIND_EPHEMERAL_HS=on
#
# EXPOSE BITCOIND RPC API AND ZMQ NOTIFICATIONS TO EXTERNAL APPS THESE
# PARAMETERS HAVE NO EFFECT IF BITCOIND_INSTALL IS SET TO OFF
#
# Expose the RPC API to external apps Warning: Do not expose your RPC API
# to internet! See BITCOIND_RPC_EXTERNAL_IP Value: on | off
BITCOIND_RPC_EXTERNAL=off
# IP address used to expose the RPC API to external apps This parameter is
# inactive if BITCOIND_RPC_EXTERNAL isn't set to 'on' Warning: Do not
# expose your RPC API to internet! Recommended value:
#   linux: 127.0.0.1 macos or windows: IP address of the VM running the
#   docker host
# Type: string
BITCOIND_RPC_EXTERNAL_IP=127.0.0.1
#
# INSTALL AND RUN BITCOIND INSIDE DOCKER
#
# Install and run bitcoind inside Docker Set this option to 'off' for using
# a bitcoind hosted outside of Docker (not recommended) Value: on | off
BITCOIND_INSTALL=off
# IP address of bitcoind used by Dojo Set value to 172.28.1.5 if
# BITCOIND_INSTALL is set to 'on' Type: string
BITCOIND_IP=172.28.0.1
# Port of the RPC API Set value to 28256 if BITCOIND_INSTALL is set to 'on'
# Type: integer
BITCOIND_RPC_PORT=8332
# Port exposing ZMQ notifications for raw transactions Set value to 9501 if
# BITCOIND_INSTALL is set to 'on' Type: integer
BITCOIND_ZMQ_RAWTXS=28333
# Port exposing ZMQ notifications for block hashes Set value to 9502 if
# BITCOIND_INSTALL is set to 'on' Type: integer
BITCOIND_ZMQ_BLK_HASH=28334
" | sudo tee -a /opt/mynode/dojo/docker/my-dojo/conf/docker-bitcoind.conf.tpl

# Turn off explorer for MyNode
sed -i 's|EXPLORER_INSTALL=on|EXPLORER_INSTALL=off|' /opt/mynode/dojo/docker/my-dojo/conf/docker-explorer.conf.tpl

# Enable electrs
sed -i 's|INDEXER_IP=.*|INDEXER_IP=172.28.0.1|' /opt/mynode/dojo/docker/my-dojo/conf/docker-indexer.conf.tpl
sed -i 's|INDEXER_BATCH_SUPPORT=.*|INDEXER_BATCH_SUPPORT=active|' /opt/mynode/dojo/docker/my-dojo/conf/docker-indexer.conf.tpl
sed -i 's|NODE_ACTIVE_INDEXER=.*|NODE_ACTIVE_INDEXER=local_indexer|' /opt/mynode/dojo/docker/my-dojo/conf/docker-node.conf.tpl


# check if configuration files have been previously created and skip if yes
if [ -f /opt/mynode/dojo/docker/my-dojo/conf/docker-node.conf ]; then
  echo "File present - skip docker-node.conf"
else
  # Modify node.conf to enter random generated passwords
  NODE_API_KEY=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c${1:-64})
  sed -i 's|NODE_API_KEY=.*|NODE_API_KEY='$NODE_API_KEY'|' /opt/mynode/dojo/docker/my-dojo/conf/docker-node.conf.tpl

  NODE_ADMIN_KEY=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c${1:-48})
  sed -i 's|NODE_ADMIN_KEY=.*|NODE_ADMIN_KEY='$NODE_ADMIN_KEY'|' /opt/mynode/dojo/docker/my-dojo/conf/docker-node.conf.tpl

  NODE_JWT_SECRET=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c${1:-48})
  sed -i 's|NODE_JWT_SECRET=.*|NODE_JWT_SECRET='$NODE_JWT_SECRET'|' /opt/mynode/dojo/docker/my-dojo/conf/docker-node.conf.tpl
fi

# check if configuration files have been previously created and skip if yes
if [ -f /opt/mynode/dojo/docker/my-dojo/conf/docker-mysql.conf ]; then
  echo "File present - skip docker-mysql.conf"
else
  # Modify mysql.conf to enter random generated passwords
  MYSQL_ROOT_PASSWORD=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c${1:-64})
  sed -i 's|MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD='$MYSQL_ROOT_PASSWORD'|' /opt/mynode/dojo/docker/my-dojo/conf/docker-mysql.conf.tpl

  MYSQL_USER=mynode
  sed -i 's|MYSQL_USER=.*|MYSQL_USER='$MYSQL_USER'|' /opt/mynode/dojo/docker/my-dojo/conf/docker-mysql.conf.tpl

  MYSQL_PASSWORD=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c${1:-64})
  sed -i 's|MYSQL_PASSWORD=.*|MYSQL_PASSWORD='$MYSQL_PASSWORD'|' /opt/mynode/dojo/docker/my-dojo/conf/docker-mysql.conf.tpl
fi

# Modify for Raspbian devices
if [ $IS_RASPI = 1 ]; then
  # Modify mysql Dockerfile for Raspbian devices
  sed -i 's|FROM.*|FROM    hypriot/rpi-mysql:latest|' /opt/mynode/dojo/docker/my-dojo/mysql/Dockerfile
  # Modify Tor Dockerfile for ARMv6/7 devices
  sed -i 's|ENV     GOLANG_ARCHIVE.*|ENV     GOLANG_ARCHIVE      go1.13.6.linux-armv6l.tar.gz|' /opt/mynode/dojo/docker/my-dojo/tor/Dockerfile
  sed -i 's|ENV     GOLANG_SHA256.*|ENV     GOLANG_SHA256       37a1a83e363dcf146a67fa839d170fd1afb13009585fdd493d0a3370fbe6f785|' /opt/mynode/dojo/docker/my-dojo/tor/Dockerfile
fi

# Modify for Rock64 devices
if [ $IS_ROCK64 = 1 ] || [ $IS_ROCKPRO64 = 1 ]; then
  # Modify mysql Dockerfile for Rock64 devices
  sed -i 's|FROM.*|FROM    mariadb:latest|' /opt/mynode/dojo/docker/my-dojo/mysql/Dockerfile
  # Modify Tor Dockerfile for ARMv8 devices
  sed -i 's|ENV     GOLANG_ARCHIVE.*|ENV     GOLANG_ARCHIVE      go1.13.6.linux-arm64.tar.gz|' /opt/mynode/dojo/docker/my-dojo/tor/Dockerfile
  sed -i 's|ENV     GOLANG_SHA256.*|ENV     GOLANG_SHA256       0a18125c4ed80f9c3045cf92384670907c4796b43ed63c4307210fe93e5bbca5|' /opt/mynode/dojo/docker/my-dojo/tor/Dockerfile
fi

# Modify restart policy
sed -i 's|restart:.*|restart: on-failure|' /opt/mynode/dojo/docker/my-dojo/docker-compose.yaml 