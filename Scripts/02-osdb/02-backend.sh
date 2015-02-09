#!/bin/bash

. support-functions

. parameters.cfg

# Variables needed to be defined
check_vars BE_NODE_1_HOSTNAME BE_NODE_1_IP BE_NODE_2_HOSTNAME BE_NODE_2_IP BE_NODE_3_HOSTNAME BE_NODE_3_IP IAAS_PASS BE_DATA_DISK OS_CTL_NET

# --------------------------------------------------------------------------------------------------------
# On all cluster nodes -----------------------------------------------------------------------------------
# --------------------------------------------------------------------------------------------------------

# Creating filesystems
pvcreate /dev/$BE_DATA_DISK
vgcreate vg_databases /dev/$BE_DATA_DISK
mkdir -p /var/lib/mysql
mkdir -p /var/lib/mongodb
lvcreate -n lv_mysql -L 20G vg_databases
lvcreate -n lv_mongodb -L 20G vg_databases
mkfs.xfs /dev/mapper/vg_databases-lv_mysql 
mkfs.xfs /dev/mapper/vg_databases-lv_mongodb
echo "/dev/mapper/vg_databases-lv_mysql      /var/lib/mysql      xfs    defaults    0 0" >> /etc/fstab 
echo "/dev/mapper/vg_databases-lv_mongodb    /var/lib/mongodb    xfs    defaults    0 0" >> /etc/fstab 
mount -a



# --------------------------------------------------------------------------------------------------------
# -------------------------   MARIADB + GALERA   ---------------------------------------------------------
# --------------------------------------------------------------------------------------------------------


# Installing software
yum install -y mariadb-galera-server xinetd rsync

# Configuring MariaDB
cat > /etc/sysconfig/clustercheck << EOF
MYSQL_USERNAME="clustercheck"
MYSQL_PASSWORD="$IAAS_PASS"
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
EOF

# Create 'clustercheck' user
systemctl start mysqld
mysql -e "CREATE USER 'clustercheck'@'localhost' IDENTIFIED BY '$IAAS_PASS';"
systemctl stop mysqld


# --------------------------------------------------------------------------------------------------------
# On one node only (node 1 in this case) -----------------------------------------------------------------
# --------------------------------------------------------------------------------------------------------

if [ "$(hostname -s)" == "$BE_NODE_1_HOSTNAME" ]; then

	# Create Galera Certs
	openssl req -new -x509 -days 3650 -nodes -keyout galera.key -out galera.crt -subj "/C=ES/ST=Madrid/L=Torrelodones/O=Spitzer Inc./OU=IT/CN= mariadb-galera" 
	# Please, be aware of CN (has the hostname of issuer and one alias to be shared with the other two nodes. In this case "mariadb-galera"
	mv galera.* /etc/pki/galera/
	chown mysql:mysql /etc/pki/galera/*
	rsync -Pav /etc/pki/galera/* root@$BE_NODE_2_NAME:/etc/pki/galera/
	rsync -Pav /etc/pki/galera/* root@$BE_NODE_3_NAME:/etc/pki/galera/
	read -i "Press enter here and in $BE_NODE_2_HOSTNAME $BE_NODE_3_HOSTNAME to continue (1): " -e
else
	read -i "Press enter when $BE_NODE_1_HOSTNAME finish the work (1): " -e
fi


# --------------------------------------------------------------------------------------------------------
# On all cluster nodes -----------------------------------------------------------------------------------
# --------------------------------------------------------------------------------------------------------

# Configuring galera.cnf file

cat > /etc/my.cnf.d/galera.cnf << EOF
[mysqld]
skip-name-resolve=1
binlog_format=ROW
default-storage-engine=innodb
innodb_autoinc_lock_mode=2
innodb_locks_unsafe_for_binlog=1
query_cache_size=0
query_cache_type=0
bind_address=$(ip -4 -o a | awk -v net="$OS_CTL_NET" '{gsub("/[0-9]+","",$4); if ($4 ~ net) print $4}')

##
## WSREP options
##

wsrep_provider=/usr/lib64/galera/libgalera_smm.so
wsrep_provider_options="socket.ssl=false; socket.ssl_cert=/etc/pki/galera/galera.crt; socket.ssl_key=/etc/pki/galera/galera.key"
wsrep_cluster_name="galera_cluster"
wsrep_slave_threads=1
wsrep_certify_nonPK=1
wsrep_max_ws_rows=131072
wsrep_max_ws_size=1073741824
wsrep_debug=0
wsrep_convert_LOCK_to_trx=0
wsrep_retry_autocommit=1
wsrep_auto_increment_control=1
wsrep_drupal_282555_workaround=0
wsrep_causal_reads=0
wsrep_notify_cmd=
wsrep_sst_method=rsync
EOF

# Configure Galera Xinetd wrapper

cat > /etc/xinetd.d/galera-monitor << EOF_XINET
service galera-monitor
{
        port            = 9200
        disable         = no
        socket_type     = stream
        protocol        = tcp
        wait            = no
        user            = root
        group           = root
        groups          = yes
        server          = /usr/bin/clustercheck
        type            = UNLISTED
        per_source      = UNLIMITED
        log_on_success = 
        log_on_failure = HOST
        flags           = REUSE
}
EOF_XINET

cat > /etc/my.cnf.d/server.cnf << EOF_SERVER_CNF
# this is read by the standalone daemon and embedded servers
[server]

# this is only for the mysqld standalone daemon
[mysqld]
max_connections = 1024
key_buffer = 1024M  
max_allowed_packet = 1024M  
thread_stack = 256K  
thread_cache_size = 1024  
query_cache_limit = 512M  
query_cache_size = 128M  
expire_logs_days = 10  
max_binlog_size = 100M 

# this is only for embedded server
[embedded]

# This group is only read by MariaDB-5.5 servers.
# If you use the same .cnf file for MariaDB of different versions,
# use this group for options that older servers don't understand
[mysqld-5.5]

# These two groups are only read by MariaDB servers, not by MySQL.
# If you use the same .cnf file for MySQL and MariaDB,
# you can put MariaDB-only options here
[mariadb]
log-error=/var/log/mariadb/mariadb.log
pid-file=/var/run/mariadb/mariadb.pid

[mariadb-5.5]

EOF_SERVER_CNF

# Starting Xinetd service
systemctl enable xinetd
systemctl start xinetd



# --------------------------------------------------------------------------------------------------------
# On one node only (node 1 in this case) -----------------------------------------------------------------
# --------------------------------------------------------------------------------------------------------

if [ "$(hostname -s)" == "$BE_NODE_1_HOSTNAME" ]; then

	# Enabling Galera in Pacemaker
	pcs resource create galera galera enable_creation=true wsrep_cluster_address="gcomm://${BE_NODE_1_HOSTNAME}-clu,${BE_NODE_2_HOSTNAME}-clu,${BE_NODE_3_HOSTNAME}-clu" meta master-max=3 ordered=true op promote timeout=300s on-fail=block --master

	# After 2-3 minutes, the Databases should be synced
	#
	# $ mysql
	# 	MariaDB [(none)]> SHOW STATUS LIKE 'wsrep%';
	# 	MariaDB [(none)]> quit

	# Populating Databases (only in one host!!)
	mysql mysql -e "
drop user ''@'$BE_NODE_1_HOSTNAME.$DOMAIN';
drop user 'root'@'$BE_NODE_1_HOSTNAME.$DOMAIN';
drop user ''@'$BE_NODE_2_HOSTNAME.$DOMAIN';
drop user 'root'@'$BE_NODE_2_HOSTNAME.$DOMAIN';
drop user ''@'$BE_NODE_3_HOSTNAME.$DOMAIN';
drop user 'root'@'$BE_NODE_3_HOSTNAME.$DOMAIN';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED by '$IAAS_PASS' WITH GRANT OPTION;
CREATE DATABASE keystone;
GRANT ALL ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$IAAS_PASS';
CREATE DATABASE glance;
GRANT ALL ON glance.* TO 'glance'@'%' IDENTIFIED BY '$IAAS_PASS';
CREATE DATABASE cinder;
GRANT ALL ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$IAAS_PASS';
CREATE DATABASE ovs_neutron;
GRANT ALL ON ovs_neutron.* TO 'neutron'@'%' IDENTIFIED BY '$IAAS_PASS';
CREATE DATABASE nova;
GRANT ALL ON nova.* TO 'nova'@'%' IDENTIFIED BY '$IAAS_PASS';
CREATE DATABASE heat;
GRANT ALL ON heat.* TO 'heat'@'%' IDENTIFIED BY '$IAAS_PASS';
FLUSH PRIVILEGES;
quit"
	mysqladmin flush-hosts

        read -i "Press enter here and in $BE_NODE_2_HOSTNAME $BE_NODE_3_HOSTNAME to continue (2): " -e
else
        read -i "Press enter when $BE_NODE_1_HOSTNAME finish the work (2): " -e
fi


# --------------------------------------------------------------------------------------------------------
# -------------------------                  RABBITMQ                -------------------------------------
# --------------------------------------------------------------------------------------------------------


# On all cluster nodes 

yum -y install rabbitmq-server
cat > /etc/rabbitmq/rabbitmq-env.conf << EOF
NODE_IP_ADDRESS=$(ip -4 -o a | awk -v net="$OS_CTL_NET" '{gsub("/[0-9]+","",$4); if ($4 ~ net) print $4}')
RABBITMQ_NODENAME=rabbit@$(hostname -s)-clu
EOF

# Required to generate the cookies
systemctl start rabbitmq-server
systemctl stop rabbitmq-server

if [ "$(hostname -s)" == "$BE_NODE_1_HOSTNAME" ]; then

	# Replicate the cookie between nodes (using node 1 as reference)
	# Execute this command only in one node

	# On every node, use the same cookie
	rsync -Pav /var/lib/rabbitmq/.erlang.cookie root@$BE_NODE_2_HOSTNAME:/var/lib/rabbitmq/
	rsync -Pav /var/lib/rabbitmq/.erlang.cookie root@$BE_NODE_3_HOSTNAME:/var/lib/rabbitmq/

	# On one node only (node 1 in this case)
	pcs resource create rabbitmq-server systemd:rabbitmq-server --clone

        read -i "Press enter here and in $BE_NODE_2_HOSTNAME $BE_NODE_3_HOSTNAME to continue (3): " -e
else
        read -i "Press enter when $BE_NODE_1_HOSTNAME finish the work (3): " -e

	# In the other two nodes (2 and 3)
	rabbitmqctl stop_app
	rabbitmqctl join_cluster rabbit@${BE_NODE_1_HOSTNAME}-clu
	rabbitmqctl start_app

fi

if [ "$(hostname -s)" == "$BE_NODE_1_HOSTNAME" ]; then
	# On one node only (node 1 in this case)
	rabbitmqctl set_policy HA '^(?!amq\.).*' '{"ha-mode": "all"}'

        read -i "Press enter here and in $BE_NODE_2_HOSTNAME $BE_NODE_3_HOSTNAME to continue (4): " -e
else
        read -i "Press enter when $BE_NODE_1_HOSTNAME finish the work (4): " -e
fi

# On all cluster nodes
rabbitmqctl cluster_status
rabbitmqctl list_policies


# --------------------------------------------------------------------------------------------------------
# -------------------------                  MONGODB                 -------------------------------------
# --------------------------------------------------------------------------------------------------------

# On all cluster nodes 
yum install -y mongodb mongodb-server

sed -i -e 's#bind_ip.*#bind_ip = 0.0.0.0#g'  /etc/mongodb.conf
echo "replSet = ceilometer" >> /etc/mongodb.conf 

# required to bootstrap mongodb
systemctl start mongod
sleep 10
systemctl stop mongod

if [ "$(hostname -s)" == "$BE_NODE_1_HOSTNAME" ]; then

	# In one node
	pcs resource create mongodb systemd:mongod --clone
	sleep 20

	# Configuring replica
	rm -f /root/mongo_replica_setup.js
	cat > /root/mongo_replica_setup.js << EOF
rs.initiate()
sleep(10000)
rs.add("${BE_NODE_1_HOSTNAME}-clu");
rs.add("${BE_NODE_2_HOSTNAME}-clu");
rs.add("${BE_NODE_3_HOSTNAME}-clu");
EOF
	mongo /root/mongo_replica_setup.js
	rm -f /root/mongo_replica_setup.js
	sleep 60

	#
	# More info: http://docs.mongodb.org/manual/tutorial/deploy-replica-set/
	#

fi
