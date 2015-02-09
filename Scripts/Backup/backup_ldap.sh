#!/bin/bash

# Info: 
#       OpenLDAP: http://www.openldap.org/doc/admin24/maintenance.html

# Requirements:
#	1. NFS mountpoints /var/lib/backups{boaw,boae} must be available


PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin"
AGE="21"
DATE="`eval date +%Y%m%d`"
LDAP_DC="dc=example,dc=com"
BACKUP_DIR="/var/lib/backups"
LDAP_BACKUP_FILE="${BACKUP_DIR}/ldap-${DATE}.tar.gz"


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

# Dump the entire LDAP database
/usr/sbin/slapcat -b $LDAP_DC -l "${BACKUP_DIR}/slapcat.ldif" > /dev/null

# If slapcat command fails, exit
if [ $? -ne 0 ]; then
    echo "ERROR!"
    echo "    'slapcat fail - Please review log files."
    exit 1
else
    rsync -Pa "/etc/openldap" "${BACKUP_DIR}/etc_openldap" > /dev/null
    tar czvf $LDAP_BACKUP_FILE -C "${BACKUP_DIR}" "slapcat.ldif" "etc_openldap" > /dev/null
    rm -rf "${BACKUP_DIR}/etc_openldap"
    rm -f "${BACKUP_DIR}/slapcat.ldif"

    # Move files to both regions: BOAW and BOAE
    cp $LDAP_BACKUP_FILE ${BACKUP_DIR}/boaw/ > /dev/null
    mv $LDAP_BACKUP_FILE ${BACKUP_DIR}/boae/ > /dev/null

    # Delete backups older than $AGE days
    find "${BACKUP_DIR}/boaw" -ctime +$AGE -type f -delete
    find "${BACKUP_DIR}/boae" -ctime +$AGE -type f -delete
fi

