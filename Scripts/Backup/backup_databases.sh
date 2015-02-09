#!/bin/bash

# Info: 
#       MySQL: https://mariadb.com/kb/en/mariadb/backup-and-restore-overview/
#	MongoDB: http://docs.mongodb.org/manual/tutorial/backup-with-mongodump/

# Requirements:
#	1. NFS mountpoints /var/lib/backups/{boaw,boae} must be mounted

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin"
BACKUP_DIR="/var/lib/backups"
DATE="`eval date +%Y%m%d`"
MYSQL_DUMP_FILE="${BACKUP_DIR}/mysql-`hostname -s`-${DATE}.sql.gz"
MYSQL_CNF_FILES="${BACKUP_DIR}/mysql-config-`hostname -s`-${DATE}.tar.gz"
MONGODB_DUMP_FILE="${BACKUP_DIR}/mongodb-`hostname -s`-${DATE}.tar.gz"
MONGODB_CNF_FILES="${BACKUP_DIR}/mongodb-config-`hostname -s`-${DATE}.tar.gz"
AGE="21"

# Check if mountpoints are available
mount | grep /var/lib/backups/boaw > /dev/null
boaw_backup_dir_is_mounted=$?
if [ $boaw_backup_dir_is_mounted -ne 0 ]; then
    echo "ERROR!"
    echo "    '/var/lib/backups/boaw' is not mounted."
    exit 1
fi


mount | grep /var/lib/backups/boae > /dev/null
boae_backup_dir_is_mounted=$?
if [ $boae_backup_dir_is_mounted -ne 0 ]; then
    echo "ERROR!"
    echo "    '/var/lib/backups/boae' is not mounted."
    exit 1
fi

# Check status of services
netstat -laputen | grep mongod > /dev/null
mongod_is_running=$?
netstat -laputen | grep mysqld > /dev/null
mysqld_is_running=$?


backup_mysql() {
# Dump the entire MySQL database
/usr/bin/mysqldump --opt --all-databases | gzip > $MYSQL_DUMP_FILE
sleep 10

# Backup MySQL config files
tar czvf $MYSQL_CNF_FILES -C "/etc" my.cnf my.cnf.d > /dev/null
}

backup_mongodb() {
# Backup MongoDB databases
mkdir -p "${BACKUP_DIR}/mongo_db_tmp"
mongodump --out "${BACKUP_DIR}/mongo_db_tmp/" > /dev/null
sleep 10
tar czvf $MONGODB_CNF_FILES -C "/etc" mongodb.conf > /dev/null
tar czvf $MONGODB_DUMP_FILE -C "${BACKUP_DIR}/mongo_db_tmp/" . > /dev/null
rm -rf "${BACKUP_DIR}/mongo_db_tmp"
}

# Backup MySQL if service is running
if [ $mysqld_is_running -eq 0 ]; then
    backup_mysql
fi
# Backup MongoDB if service is running
if [ $mongod_is_running -eq 0 ]; then
    backup_mongodb
fi

# Move files to both regions: BOAW and BOAE
cp ${BACKUP_DIR}/*.gz ${BACKUP_DIR}/boaw/ > /dev/null
mv ${BACKUP_DIR}/*.gz ${BACKUP_DIR}/boae/ > /dev/null

# Delete backups older than $AGE days
find "${BACKUP_DIR}/boaw" -ctime +$AGE -type f -delete
find "${BACKUP_DIR}/boae" -ctime +$AGE -type f -delete

