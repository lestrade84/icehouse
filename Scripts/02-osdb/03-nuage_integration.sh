#!/bin/bash

. support-functions

. parameters.cfg

# Variables needed to be defined
check_vars IAAS_PASS BE_NODE_1_HOSTNAME

# ------------------------------------------------------------------------------------------------------------

if [ "$(hostname -s)" == "$BE_NODE_1_HOSTNAME" ]; then

	# On one backend server
	mysql <<EOF
create database nuage_neutron;
grant all privileges on nuage_neutron.* to 'nuage_neutron'@'localhost' identified by '$IAAS_PASS';
grant all privileges on nuage_neutron.* to 'nuage_neutron'@'%' identified by '$IAAS_PASS';
flush privileges;
EOF

fi
