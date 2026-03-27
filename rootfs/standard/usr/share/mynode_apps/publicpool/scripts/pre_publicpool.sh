#!/bin/bash

# This will run prior to launching the application
echo """
# bitcoin node running in your private network 192.168.1.0/24
BITCOIN_RPC_URL=http://localhost
# If running in docker...
#BITCOIN_RPC_URL=http://host.docker.internal

BITCOIN_RPC_USER=
BITCOIN_RPC_PASSWORD=
BITCOIN_RPC_PORT=8332
BITCOIN_RPC_TIMEOUT=10000

# You can use this instead of BITCOIN_RPC_USER and BITCOIN_RPC_PASSWORD
BITCOIN_RPC_COOKIEFILE=/mnt/hdd/mynode/bitcoin/.cookie

# Enable in bitcoin.conf with zmqpubrawblock=...
BITCOIN_ZMQ_HOST="tcp://localhost:28332"

API_PORT=3334
STRATUM_PORT=3333

#optional telegram bot
#TELEGRAM_BOT_TOKEN=

#optional discord bot
#DISCORD_BOT_CLIENTID=
#DISCORD_BOT_GUILD_ID=
#DISCORD_BOT_CHANNEL_ID=

#optional
DEV_FEE_ADDRESS=

# mainnet | testnet
NETWORK=mainnet

API_SECURE=false
# Default is "Public-Pool", you can change it to any string it will be removed if it will make the block or coinbase script too big
POOL_IDENTIFIER="Public-Pool on MyNode"
""" > /opt/mynode/publicpool/.env