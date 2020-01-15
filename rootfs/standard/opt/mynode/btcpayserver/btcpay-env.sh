#!/bin/bash
export COMPOSE_HTTP_TIMEOUT="180"
export BTCPAYGEN_OLD_PREGEN="false"
export BTCPAYGEN_CRYPTO1="btc"
export BTCPAYGEN_CRYPTO2=""
export BTCPAYGEN_CRYPTO3=""
export BTCPAYGEN_CRYPTO4=""
export BTCPAYGEN_CRYPTO5=""
export BTCPAYGEN_CRYPTO6=""
export BTCPAYGEN_CRYPTO7=""
export BTCPAYGEN_CRYPTO8=""
export BTCPAYGEN_CRYPTO9=""
export BTCPAYGEN_LIGHTNING="lnd"
export BTCPAYGEN_REVERSEPROXY="nginx"
export BTCPAYGEN_ADDITIONAL_FRAGMENTS=""
export BTCPAYGEN_EXCLUDE_FRAGMENTS="opt-add-tor"
export BTCPAY_DOCKER_COMPOSE="/opt/mynode/btcpayserver/docker-compose.generated.yml"
export BTCPAY_BASE_DIRECTORY="/opt/mynode/btcpayserver"
export BTCPAY_ENV_FILE="/opt/mynode/btcpayserver/.env"
export BTCPAY_HOST_SSHKEYFILE=""
export BTCPAY_ENABLE_SSH=true
if cat "$BTCPAY_ENV_FILE" &> /dev/null; then
  while IFS= read -r line; do
    ! [[ "$line" == "#"* ]] && [[ "$line" == *"="* ]] && export "$line"
  done < "$BTCPAY_ENV_FILE"
fi
