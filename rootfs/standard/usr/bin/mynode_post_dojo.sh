#!/bin/bash

set -e

source /usr/share/mynode/mynode_config.sh

sleep 30s #dojo needs time to start before passing next line

# initalize mysql db (REQUIRED TO START MYSQL)
counter=0
target=200
isRunning=""
MYSQL_DATABASE=samourai-main

# check on loop if  mysql db is running. when running initialize
while [ $counter != $target ]
do

  source /opt/mynode/dojo/docker/my-dojo/conf/docker-mysql.conf || exit 0

  # Check if dojo mysql db is running (check the db container)
  isRunning=$(docker inspect --format="{{.State.Running}}" db)
  if [ "$isRunning" == "true" ]; then
    sleep 60s
    if [ $IS_RASPI = 1 ]; then
        docker exec -i db bash -c "mysql -h db -u root -p$MYSQL_ROOT_PASSWORD $MYSQL_DATABASE" </opt/mynode/dojo/db-scripts/1_db.sql
    fi
    echo "dojo mysql db initalized"
    sleep 5s
    # Stop dojo after install/update and initalization is complete
    cd /opt/mynode/dojo/docker/my-dojo
    sudo ./dojo.sh stop
    counter=$target
  else
    echo "waiting to initalize dojo mysql db - retrying $[ $target-$counter ] more times"
    counter=$(( $counter + 1 ))
    sleep 30s
  fi
done || exit 0
