#!/bin/bash

set -x

source /usr/share/mynode/mynode_config.sh

sleep 10s

# initalize mysql db (REQUIRED TO START MYSQL)
isRunning=""

# check on loop if  mysql db is running. when running initialize
while [ 1 ]; do
  # Check if mempool mysql db is running (check the db container)
  isRunning=$(docker inspect --format="{{.State.Running}}" mempool_db_1)
  if [ "$isRunning" == "true" ]; then
    sleep 5s
    blocks=$(docker exec -i mempool_db_1 mysql -uroot -padmin -D mempool -e "show tables;" | grep blocks)
    if [[ "$blocks" == *"blocks"* ]]; then
        echo "Mempool DB initialized!"
        exit 0;
    fi
    if [ $IS_RASPI == 1 ]; then
        echo "Initializing mempool db..."
        docker exec -i mempool_db_1 bash -c "mysql -u root -padmin mempool" </mnt/hdd/mynode/mempool/mysql/db-scripts/mariadb-structure.sql
        if [ $? -eq 0 ]; then
            echo "Import success. Restart service by exiting 1."
            exit 1
        fi
    fi
  else
    echo "Waiting to initialize mempool DB..."
    sleep 10s
  fi
done

exit 0
