#!/bin/bash

set -x

source /usr/share/mynode/mynode_config.sh
source /usr/share/mynode/mynode_app_versions.sh

sleep 10s

# initalize mysql db (REQUIRED TO START MYSQL)
isRunning=""

# Initialize databse must be done manually on old mempool versions
if [ "$MEMPOOL_VERSION" = "v2.3.1" ]; then
    # check on loop if  mysql db is running. when running initialize
    while [ 1 ]; do
    # Check if mempool mysql db is running (check the db container)
    isRunning=$(docker inspect --format="{{.State.Running}}" mempool_db_1)
    if [ "$isRunning" == "true" ]; then
        sleep 5s

        # Initialize database
        databases=$(docker exec -i mempool_db_1 mysql -uroot -padmin -e "SHOW DATABASES;")
        if [[ "$databases" == *"information_schema"* ]]; then   # Check DB is responding
            if [[ "$databases" == *"mempool"* ]]; then
                # DB found, exit 0
                exit 0
            else
                # Setup a database for mempool
                $(docker exec -i mempool_db_1 mysql -uroot -padmin -e "drop database mempool;")
                $(docker exec -i mempool_db_1 mysql -uroot -padmin -e "create database mempool;")
                $(docker exec -i mempool_db_1 mysql -uroot -padmin -e "grant all privileges on mempool.* to 'mempool'@'%' identified by 'mempool';")
                exit 0
            fi
        fi

    else
        echo "Waiting to initialize mempool DB..."
        sleep 10s
    fi
    done
fi

exit 0
