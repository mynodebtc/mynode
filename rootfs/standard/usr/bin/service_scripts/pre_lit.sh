#!/bin/bash

# LiT v0.17+ migrates its bbolt stores (accounts, sessions, firewall rules) to
# SQLite on first startup. That migration is one-way - it tombstones the bbolt
# files in place without saving a copy anywhere, and LiT cannot be downgraded
# below v0.17 once it has run. Save a copy before litd gets the chance.

NETWORK=mainnet
if [ -f /mnt/hdd/mynode/settings/.testnet_enabled ]; then
    NETWORK=testnet
fi

LIT_NETWORK_DIR=/mnt/hdd/mynode/lit/$NETWORK
LIT_BACKUP_DIR=$LIT_NETWORK_DIR/bbolt_backup_pre_sql
LIT_BBOLT_DBS="accounts.db session.db rules.db macaroons.db"

# This runs on every start (the lit service restarts automatically), so bail
# out cheaply once the backup exists.
if [ -d $LIT_BACKUP_DIR ]; then
    exit 0
fi

# Skip if the migration already ran - any bbolt files still sitting there have
# been tombstoned and are not worth saving.
if [ -f $LIT_NETWORK_DIR/litd.db ]; then
    exit 0
fi

# Find which bbolt databases exist and how much space a copy needs
BACKUP_DBS=""
BACKUP_SIZE_KB=0
for DB in $LIT_BBOLT_DBS; do
    if [ -f $LIT_NETWORK_DIR/$DB ]; then
        BACKUP_DBS="$BACKUP_DBS $DB"
        DB_SIZE_KB=$(du -k $LIT_NETWORK_DIR/$DB | awk '{print $1}')
        BACKUP_SIZE_KB=$((BACKUP_SIZE_KB + DB_SIZE_KB))
    fi
done

# Nothing to back up (fresh install)
if [ "$BACKUP_DBS" = "" ]; then
    exit 0
fi

# Make sure there is room, with margin. Blocking startup is deliberate here -
# letting litd run the migration without a backup is not recoverable.
FREE_SPACE_KB=$(df -k --output=avail $LIT_NETWORK_DIR | tail -n 1)
if [ "$FREE_SPACE_KB" -lt $((BACKUP_SIZE_KB * 2)) ]; then
    echo "ERROR: not enough free space to back up LiT databases before the SQL"
    echo "       migration (need ${BACKUP_SIZE_KB}KB, have ${FREE_SPACE_KB}KB)."
    echo "       Refusing to start litd. Free up space on the drive."
    exit 1
fi

# Copy to a temp folder first so a partial copy can never be mistaken for a
# complete backup
echo "Backing up LiT databases before SQL migration:$BACKUP_DBS"
rm -rf $LIT_BACKUP_DIR.tmp
mkdir -p $LIT_BACKUP_DIR.tmp
for DB in $BACKUP_DBS; do
    if ! cp -a $LIT_NETWORK_DIR/$DB $LIT_BACKUP_DIR.tmp/$DB ; then
        echo "ERROR: failed to back up $DB before the LiT SQL migration."
        echo "       Refusing to start litd."
        rm -rf $LIT_BACKUP_DIR.tmp
        exit 1
    fi
done
sync
mv $LIT_BACKUP_DIR.tmp $LIT_BACKUP_DIR
sync
echo "LiT database backup saved to $LIT_BACKUP_DIR"

exit 0
