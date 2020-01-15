btcpay_up() {
    pushd . > /dev/null
    cd "$(dirname "$BTCPAY_ENV_FILE")"
    docker-compose -f $BTCPAY_DOCKER_COMPOSE up --remove-orphans -d -t "${COMPOSE_HTTP_TIMEOUT:-180}"
    # Depending on docker-compose, either the timeout does not work, or "compose -d and --timeout cannot be combined"
    if ! [ $? -eq 0 ]; then
        docker-compose -f $BTCPAY_DOCKER_COMPOSE up --remove-orphans -d
    fi
    popd > /dev/null
}

btcpay_pull() {
    pushd . > /dev/null
    cd "$(dirname "$BTCPAY_ENV_FILE")"
    docker-compose -f "$BTCPAY_DOCKER_COMPOSE" pull
    popd > /dev/null
}

btcpay_down() {
    pushd . > /dev/null
    cd "$(dirname "$BTCPAY_ENV_FILE")"
    docker-compose -f $BTCPAY_DOCKER_COMPOSE down -t "${COMPOSE_HTTP_TIMEOUT:-180}"
    # Depending on docker-compose, the timeout does not work.
    if ! [ $? -eq 0 ]; then
        docker-compose -f $BTCPAY_DOCKER_COMPOSE down
    fi
    popd > /dev/null
}

btcpay_restart() {
    pushd . > /dev/null
    cd "$(dirname "$BTCPAY_ENV_FILE")"
    docker-compose -f $BTCPAY_DOCKER_COMPOSE restart -t "${COMPOSE_HTTP_TIMEOUT:-180}"
    # Depending on docker-compose, the timeout does not work.
    if ! [ $? -eq 0 ]; then
        docker-compose -f $BTCPAY_DOCKER_COMPOSE restart
    fi
    popd > /dev/null
}