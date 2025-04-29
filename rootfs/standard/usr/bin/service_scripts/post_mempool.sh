#!/bin/bash

set -x

source /usr/share/mynode/mynode_config.sh

sleep 10s

# Check Docker Compose version
compose_version=$(docker-compose --version)

if [[ $compose_version == *"v2."* ]]; then
  separator="-"
else
  separator="_"
fi

export DB_CONTAINER_NAME="mempool${separator}db${separator}1"

# initialize mysql db (REQUIRED TO START mysql)
isRunning=""

# Check on loop if mysql db is running; when running, initialize
while [ 1 ]; do
  # Check if mempool mysql db is running (check the db container)
  isRunning=$(docker inspect --format="{{.State.Running}}" $DB_CONTAINER_NAME)
  if [ "$isRunning" == "true" ]; then
    sleep 5s

    # Initialize database
    databases=$(docker exec -i $DB_CONTAINER_NAME mysql -uroot -padmin -e "SHOW DATABASES;")
    if [[ "$databases" == *"information_schema"* ]]; then   # Check DB is responding
        if [[ "$databases" == *"mempool"* ]]; then
            # DB found, exit 0
            exit 0
        else
            # Setup a database for mempool
            $(docker exec -i $DB_CONTAINER_NAME mysql -uroot -padmin -e "drop database mempool;")
            $(docker exec -i $DB_CONTAINER_NAME mysql -uroot -padmin -e "create database mempool;")
            $(docker exec -i $DB_CONTAINER_NAME mysql -uroot -padmin -e "grant all privileges on mempool.* to 'mempool'@'%' identified by 'mempool';")
            exit 0
        fi
    fi

  else
    echo "Waiting to initialize mempool DB..."
    sleep 10s
  fi
done

exit 0
