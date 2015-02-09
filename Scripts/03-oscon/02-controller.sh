#!/bin/bash

. support-functions

. parameters.cfg

# Variables needed to be defined
check_vars CON_NODE_1_HOSTNAME CON_NODE_1_IP CON_NODE_2_HOSTNAME CON_NODE_2_IP CON_NODE_3_HOSTNAME CON_NODE_3_IP IAAS_PASS DOMAIN PUBLIC_DOMAIN OS_CTL_NET INBAND_MGMT_NET VIP_HORIZON VIP_MYSQL VIP_KEYSTONE VIP_GLANCE VIP_CINDER VIP_SWIFT VIP_NEUTRON VIP_NOVA VIP_HEAT VIP_MONGO VIP_CEILOMETER VIP_LDAP VIP_VSD BE_NODE_1_IP BE_NODE_2_IP BE_NODE_3_IP LDAP_URL LDAPS_URL LDAP_SUFFIX LDAP_USER_TREE LDAP_USER LDAP_GROUP_TREE REGION_NAME DEFAULT_AZ REPO_SERVER OS_SERVICE_TOKEN

NODE_IP=$(ip -4 -o a | awk -v net="$OS_CTL_NET" '{gsub("/[0-9]+","",$4); if ($4 ~ net) print $4}')

# --------------------------------------------------------------------------------------------------------
# -------------------------                  MEMCACHED                         ---------------------------
# --------------------------------------------------------------------------------------------------------


# On all cluster nodes
yum install -y memcached

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	# On one node only
	pcs resource create memcached systemd:memcached --clone

        read -i "Press enter here and in $CON_NODE_2_HOSTNAME $CON_NODE_3_HOSTNAME to continue (1): " -e
else
        read -i "Press enter when $CON_NODE_1_HOSTNAME finish the work (1): " -e
fi


# --------------------------------------------------------------------------------------------------------
# -------------------------                   KEYSTONE                         ---------------------------
# --------------------------------------------------------------------------------------------------------

# On all cluster nodes --------------------
yum install -y openstack-keystone openstack-utils

# We need to generate an OS_SERVICE_TOKEN and it must be the same on all nodes. It´s not important HOW it is set. This is just one way.
openstack-config --set /etc/keystone/keystone.conf DEFAULT admin_token $OS_SERVICE_TOKEN

# Rabbitmq configuration
openstack-config --set /etc/keystone/keystone.conf DEFAULT rabbit_ha_queues true
openstack-config --set /etc/keystone/keystone.conf DEFAULT rabbit_hosts $BE_NODE_1_IP:5672,$BE_NODE_2_IP:5672,$BE_NODE_3_IP:5672

# Keystone API endpoints
openstack-config --set /etc/keystone/keystone.conf DEFAULT admin_endpoint 'http://$VIP_KEYSTONE:%(admin_port)s/'
openstack-config --set /etc/keystone/keystone.conf DEFAULT public_endpoint 'http://$VIP_KEYSTONE:%(public_port)s/'

# MariaDB configuration - Make sure to retry connection to the DB if the DB is not available immediately at service startup
openstack-config --set /etc/keystone/keystone.conf database connection mysql://keystone:$IAAS_PASS@$VIP_MYSQL/keystone
openstack-config --set /etc/keystone/keystone.conf database max_retries -1
openstack-config --set /etc/keystone/keystone.conf database idle_timeout 60

# Make sure the API service is listening on the internal IP addresses only.
openstack-config --set /etc/keystone/keystone.conf DEFAULT public_bind_host $NODE_IP
openstack-config --set /etc/keystone/keystone.conf DEFAULT admin_bind_host $NODE_IP

# Configure MariaDB (mysql) backend for tokens
openstack-config --set /etc/keystone/keystone.conf TOKEN driver keystone.token.backends.sql.Token

# Schedule and delete old Keystone Tokens hourly basis
case $(hostname -s|rev|cut -c 1) in
  1)
    echo "1,4,7,10,13,16,19,22 * * * * keystone /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1" > /etc/cron.d/keystone
    ;;
  2)
    echo "2,5,8,11,14,17,20,23 * * * * keystone /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1" > /etc/cron.d/keystone
    ;;
  3)
    echo "3,6,9,12,15,18,21,00 * * * * keystone /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1" > /etc/cron.d/keystone
    ;;
esac

# --------------------------------------
# On one node only ---------------------
# --------------------------------------

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	# Create and sync keystone ssl certificates. One more time, this is just one way to propagate them between nodes, but as long as they are the same on all nodes, it should work just fine.
	keystone-manage pki_setup --keystone-user keystone --keystone-group keystone
	chown -R keystone:keystone /var/log/keystone /etc/keystone/ssl/
	cd /etc/keystone/ssl/
	tar cvp -f keystone_ssl.tar *
	rsync -Pav keystone_ssl.tar root@$CON_NODE_2_HOSTNAME:
	rsync -Pav keystone_ssl.tar root@$CON_NODE_3_HOSTNAME:
	rm -f keystone_ssl.tar
	cd ~

        read -i "Press enter here and in $CON_NODE_2_HOSTNAME $CON_NODE_3_HOSTNAME to continue (2): " -e
else
        read -i "Press enter when $CON_NODE_1_HOSTNAME finish the work (2): " -e

	# On the other two nodes----------------
	mkdir -p /etc/keystone/ssl
	cd /etc/keystone/ssl
	tar xvp -f /root/keystone_ssl.tar
	chown -R keystone:keystone /var/log/keystone /etc/keystone/ssl/
	rm -f /root/keystone_ssl.tar

fi

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	# On one node only ---------------------
	su keystone -s /bin/sh -c "keystone-manage db_sync"
	pcs resource create keystone systemd:openstack-keystone --clone

        read -i "Press enter here and in $CON_NODE_2_HOSTNAME $CON_NODE_3_HOSTNAME to continue (3): " -e
else
        read -i "Press enter when $CON_NODE_1_HOSTNAME finish the work (3): " -e
fi

# On all nodes -------------------------

#
# LDAP Integration: http://docs.openstack.org/admin-guide-cloud/content/configuring-keystone-for-ldap-backend.html
#
# Enable the LDAP driver in the 'keystone.conf' file
openstack-config --set /etc/keystone/keystone.conf IDENTITY driver keystone.identity.backends.ldap.Identity
# Define the destination LDAP server in the 'keystone.conf' file
openstack-config --set /etc/keystone/keystone.conf LDAP url $LDAP_URL
openstack-config --set /etc/keystone/keystone.conf LDAP user $LDAP_USER
openstack-config --set /etc/keystone/keystone.conf LDAP password $IAAS_PASS
openstack-config --set /etc/keystone/keystone.conf LDAP suffix $LDAP_SUFFIX
openstack-config --set /etc/keystone/keystone.conf LDAP use_dumb_member False
openstack-config --set /etc/keystone/keystone.conf LDAP allow subtree_delete False
openstack-config --set /etc/keystone/keystone.conf LDAP use_tls True
openstack-config --set /etc/keystone/keystone.conf LDAP tls_req_cert allow
openstack-config --set /etc/keystone/keystone.conf LDAP tls_cacertfile /etc/keystone/cacert.asc
# Define the OU's in the LDAP directory. Then define the corresponding location in the 'keystone.conf' file
openstack-config --set /etc/keystone/keystone.conf LDAP user_tree_dn $LDAP_USER_TREE
openstack-config --set /etc/keystone/keystone.conf LDAP user_objectclass inetOrgPerson
openstack-config --set /etc/keystone/keystone.conf LDAP group_tree_dn $LDAP_GROUP_TREE
openstack-config --set /etc/keystone/keystone.conf LDAP group_objectclass groupOfNames
openstack-config --set /etc/keystone/keystone.conf LDAP group_id_attribute cn
openstack-config --set /etc/keystone/keystone.conf LDAP group_name_attribute cn
openstack-config --set /etc/keystone/keystone.conf LDAP group_member_attribute member
openstack-config --set /etc/keystone/keystone.conf LDAP group_desc_attribute description
# Additional options
openstack-config --set /etc/keystone/keystone.conf LDAP user_id_attribute cn
openstack-config --set /etc/keystone/keystone.conf LDAP user_name_attribute cn
openstack-config --set /etc/keystone/keystone.conf LDAP user_mail_attribute mail
openstack-config --set /etc/keystone/keystone.conf LDAP user_enabled_emulation true
openstack-config --set /etc/keystone/keystone.conf LDAP user_enabled_emulation_dn cn=enabled_users,ou=groups,ou=openstack,dc=example,dc=com
openstack-config --set /etc/keystone/keystone.conf ASSIGNMENT driver keystone.assignment.backends.sql.Assignment
# Applying read-only to LDAP configuration
openstack-config --set /etc/keystone/keystone.conf LDAP user_allow_create False
openstack-config --set /etc/keystone/keystone.conf LDAP user_allow_update False
openstack-config --set /etc/keystone/keystone.conf LDAP user_allow_delete False
openstack-config --set /etc/keystone/keystone.conf LDAP group_allow_create False
openstack-config --set /etc/keystone/keystone.conf LDAP group_allow_update False
openstack-config --set /etc/keystone/keystone.conf LDAP group_allow_delete False

# Configure LDAP over TLS
openstack-config --set /etc/keystone/keystone.conf LDAP use_tls True
openstack-config --set /etc/keystone/keystone.conf LDAP tls_req_cert allow
openstack-config --set /etc/keystone/keystone.conf LDAP tls_cacertfile /etc/keystone/cacert.asc
wget -O /etc/keystone/cacert.asc http://$REPO_SERVER/ca-certs/cacert.asc

# On one node only ---------------------

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	# Creating keystone endpoint
	keystone service-create --name=keystone --type=identity --description="Keystone Identity Service"
	keystone endpoint-create --service keystone --region $REGION_NAME --publicurl "http://keystone.${PUBLIC_DOMAIN}:5000/v2.0" --adminurl "http://$VIP_KEYSTONE:35357/v2.0" --internalurl "http://$VIP_KEYSTONE:5000/v2.0"

	# Creating admin user structures (the user must be created on LDAP server before!)
	keystone role-create --name admin
	keystone tenant-create --name admin
	keystone user-role-add --user admin --role admin --tenant admin
	cat > /root/keystonerc_admin << EOF
export OS_USERNAME=admin 
export OS_TENANT_NAME=admin
export OS_PASSWORD=$IAAS_PASS
export OS_AUTH_URL=http://$VIP_KEYSTONE:35357/v2.0/
export PS1='[\u@\h \W(keystone_admin)]\$ '
EOF

	# Create 'test' user structures (the user 'test' must be already created on LDAP server) for test purposes
	keystone role-create --name Member
	keystone tenant-create --name TENANT
	keystone user-role-add --user 'test' --role Member --tenant TENANT
	# Save user credential in a file for testing purposes.
	cat > /root/keystonerc_user << EOF
export OS_USERNAME=test
export OS_TENANT_NAME=TENANT
export OS_PASSWORD=$IAAS_PASS
export OS_AUTH_URL=http://$VIP_KEYSTONE:5000/v2.0/
export PS1='[\u@\h \W(keystone_user)]\$ '
EOF

	# Populate keystonerc_ keys
	rsync -Pav /root/keystonerc_* root@$CON_NODE_2_HOSTNAME:
	rsync -Pav /root/keystonerc_* root@$CON_NODE_3_HOSTNAME:

	# Create 'services' tenant
	keystone tenant-create --name services --description "Services Tenant"

	# Create endpoints for each service

	# glance - the user 'glance' must be already created on LDAP server
	keystone user-role-add --user glance --role admin --tenant services
	keystone service-create --name glance --type image --description "Glance Image Service"
	keystone endpoint-create --service glance --region $REGION_NAME --publicurl "http://glance.${PUBLIC_DOMAIN}:9292" --adminurl "http://$VIP_GLANCE:9292" --internalurl "http://$VIP_GLANCE:9292"

	# cinder - the user 'cinder' must be already created on LDAP server
	keystone user-role-add --user cinder --role admin --tenant services
	keystone service-create --name cinder --type volume --description "Cinder Volume Service"
	keystone endpoint-create --service cinder --region $REGION_NAME --publicurl "http://cinder.${PUBLIC_DOMAIN}:8776/v1/%(tenant_id)s" --adminurl "http://$VIP_CINDER:8776/v1/%(tenant_id)s" --internalurl "http://$VIP_CINDER:8776/v1/%(tenant_id)s"

	# swift - the user 'swift' must be already created on LDAP server
	#keystone user-role-add --user swift --role admin --tenant services
	#keystone service-create --name swift --type object-store --description "Swift Storage Service"
	#keystone endpoint-create --service swift --region $REGION_NAME --publicurl "http://swift.${PUBLIC_DOMAIN}:8080/v1/AUTH_%(tenant_id)s" --adminurl "http://$VIP_SWIFT:8080/v1" --internalurl "http://$VIP_SWIFT:8080/v1/AUTH_%(tenant_id)s"

	# neutron - the user 'neutron' must be already created on LDAP server
	keystone user-role-add --user neutron --role admin --tenant services
	keystone service-create --name neutron --type network --description "OpenStack Neutron Service"
	keystone endpoint-create --service neutron --region $REGION_NAME --publicurl "http://neutron.${PUBLIC_DOMAIN}:9696" --adminurl "http://$VIP_NEUTRON:9696" --internalurl "http://$VIP_NEUTRON:9696"

	# nova - the user 'compute' must be already created on LDAP server
	keystone user-role-add --user compute --role admin --tenant services
	keystone service-create --name compute --type compute --description "OpenStack Compute Service"
	keystone endpoint-create  --service compute --region $REGION_NAME --publicurl "http://nova.${PUBLIC_DOMAIN}:8774/v2/%(tenant_id)s" --adminurl "http://$VIP_NOVA:8774/v2/%(tenant_id)s" --internalurl "http://$VIP_NOVA:8774/v2/%(tenant_id)s"

	# heat - the user 'heat' must be already created on LDAP server
	keystone user-role-add --user heat --role admin --tenant services
	keystone service-create --name heat --type orchestration
	keystone endpoint-create --service heat --region $REGION_NAME --publicurl "http://heat.${PUBLIC_DOMAIN}:8004/v1/%(tenant_id)s" --adminurl "http://$VIP_HEAT:8004/v1/%(tenant_id)s" --internalurl "http://$VIP_HEAT:8004/v1/%(tenant_id)s"
	keystone service-create --name heat-cfn --type cloudformation
	keystone endpoint-create --service heat-cfn --region $REGION_NAME --publicurl "http://heat.${PUBLIC_DOMAIN}:8000/v1" --adminurl "http://$VIP_HEAT:8000/v1" --internalurl "http://$VIP_HEAT:8000/v1"

	# ceilometer - the user 'ceilometer' must be already created on LDAP server
	keystone user-role-add --user ceilometer --role admin --tenant services
	keystone role-create --name ResellerAdmin
	keystone user-role-add --user ceilometer --role ResellerAdmin --tenant services
	keystone service-create --name ceilometer --type metering --description="OpenStack Telemetry Service"
	keystone endpoint-create --service ceilometer --region $REGION_NAME --publicurl "http://ceilometer.${PUBLIC_DOMAIN}:8777" --adminurl "http://$VIP_CEILOMETER:8777" --internalurl "http://$VIP_CEILOMETER:8777"

        read -i "Press enter here and in $CON_NODE_2_HOSTNAME $CON_NODE_3_HOSTNAME to continue (4): " -e
else
        read -i "Press enter when $CON_NODE_1_HOSTNAME finish the work (4): " -e
fi


# --------------------------------------------------------------------------------------------------------
# -------------------------                     GLANCE                         ---------------------------
# --------------------------------------------------------------------------------------------------------

# On all cluster nodes --------------------

# Install Software
yum install -y openstack-glance openstack-utils

# Configure the API service 
openstack-config --set /etc/glance/glance-api.conf database connection mysql://glance:$IAAS_PASS@$VIP_MYSQL/glance
openstack-config --set /etc/glance/glance-api.conf database max_retries -1
openstack-config --set /etc/glance/glance-api.conf database idle_timeout 60
openstack-config --set /etc/glance/glance-api.conf paste_deploy flavor keystone
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_host $VIP_KEYSTONE
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_port 35357
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_protocol http
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken admin_tenant_name services
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken admin_user glance
openstack-config --set /etc/glance/glance-api.conf keystone_authtoken admin_password $IAAS_PASS
openstack-config --set /etc/glance/glance-api.conf DEFAULT notification_driver messaging
openstack-config --set /etc/glance/glance-api.conf DEFAULT rabbit_ha_queues true
openstack-config --set /etc/glance/glance-api.conf DEFAULT rabbit_hosts $BE_NODE_1_IP:5672,$BE_NODE_2_IP:5672,$BE_NODE_3_IP:5672
openstack-config --set /etc/glance/glance-api.conf DEFAULT registry_host $VIP_GLANCE
openstack-config --set /etc/glance/glance-api.conf DEFAULT bind_host $NODE_IP

# Configure the registry service
openstack-config --set /etc/glance/glance-registry.conf database connection mysql://glance:$IAAS_PASS@$VIP_MYSQL/glance
openstack-config --set /etc/glance/glance-registry.conf database max_retries -1
openstack-config --set /etc/glance/glance-registry.conf database idle_timeout 60
openstack-config --set /etc/glance/glance-registry.conf paste_deploy flavor keystone
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken auth_host $VIP_KEYSTONE
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken auth_port 35357
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken auth_protocol http
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken admin_tenant_name services
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken admin_user glance
openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken admin_password $IAAS_PASS
openstack-config --set /etc/glance/glance-registry.conf DEFAULT bind_host $NODE_IP

# On one node only ------------------------

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	# Populate the glance db entries
	su glance -s /bin/sh -c "glance-manage db_sync"

	# We use NFS mountpoint (10.5.128.35:/glance) for test purposes. Right here we will use the Ceph integration commands

	# Creating the rest of PCS resources
	pcs resource create glance-registry systemd:openstack-glance-registry --clone
	pcs resource create glance-api systemd:openstack-glance-api --clone
	pcs constraint order start glance-registry-clone then glance-api-clone
	pcs constraint colocation add glance-api-clone with glance-registry-clone

        read -i "Press enter here and in $CON_NODE_2_HOSTNAME $CON_NODE_3_HOSTNAME to continue (5): " -e
else
        read -i "Press enter when $CON_NODE_1_HOSTNAME finish the work (5): " -e
fi


# --------------------------------------------------------------------------------------------------------
# -------------------------                     CINDER                         ---------------------------
# --------------------------------------------------------------------------------------------------------

# On all cluster nodes --------------------

# Install Software
yum install -y openstack-cinder openstack-utils python-memcached

openstack-config --set /etc/cinder/cinder.conf database connection mysql://cinder:$IAAS_PASS@$VIP_MYSQL/cinder
openstack-config --set /etc/cinder/cinder.conf database max_retries -1
openstack-config --set /etc/cinder/cinder.conf database idle_timeout 60
openstack-config --set /etc/cinder/cinder.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/cinder/cinder.conf keystone_authtoken auth_host $VIP_KEYSTONE
openstack-config --set /etc/cinder/cinder.conf keystone_authtoken admin_tenant_name services
openstack-config --set /etc/cinder/cinder.conf keystone_authtoken admin_user cinder
openstack-config --set /etc/cinder/cinder.conf keystone_authtoken admin_password $IAAS_PASS
openstack-config --set /etc/cinder/cinder.conf DEFAULT notification_driver messaging
openstack-config --set /etc/cinder/cinder.conf DEFAULT control_exchange cinder
openstack-config --set /etc/cinder/cinder.conf DEFAULT rabbit_ha_queues true
openstack-config --set /etc/cinder/cinder.conf DEFAULT rabbit_hosts $BE_NODE_1_IP:5672,$BE_NODE_2_IP:5672,$BE_NODE_3_IP:5672
openstack-config --set /etc/cinder/cinder.conf DEFAULT glance_host $VIP_GLANCE
openstack-config --set /etc/cinder/cinder.conf DEFAULT memcache_servers $CON_NODE_1_IP:11211,$CON_NODE_2_IP:11211,$CON_NODE_3_IP:11211
openstack-config --set /etc/cinder/cinder.conf DEFAULT host cinder-$DEFAULT_AZ
openstack-config --set /etc/cinder/cinder.conf DEFAULT osapi_volume_listen $NODE_IP

# Fix the NOFILE for Cinder service
cat > /usr/lib/systemd/system/openstack-cinder-volume.service << EOF
[Unit]
Description=OpenStack Cinder Volume Server
After=syslog.target network.target

[Service]
Type=simple
User=cinder
ExecStart=/usr/bin/cinder-volume --config-file /usr/share/cinder/cinder-dist.conf --config-file /etc/cinder/cinder.conf --logfile /var/log/cinder/volume.log
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
EOF

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	# On one node only ------------------------
	su cinder -s /bin/sh -c "cinder-manage db sync"
	pcs resource create cinder-api systemd:openstack-cinder-api --clone
	pcs resource create cinder-scheduler systemd:openstack-cinder-scheduler --clone
	pcs resource create cinder-volume-$DEFAULT_AZ systemd:openstack-cinder-volume
	pcs constraint order start cinder-api-clone then cinder-scheduler-clone
	pcs constraint colocation add cinder-scheduler-clone with cinder-api-clone
	pcs constraint order start cinder-scheduler-clone then cinder-volume-$DEFAULT_AZ
	pcs constraint colocation add cinder-volume-$DEFAULT_AZ with cinder-scheduler-clone

        read -i "Press enter here and in $CON_NODE_2_HOSTNAME $CON_NODE_3_HOSTNAME to continue (6): " -e
else
        read -i "Press enter when $CON_NODE_1_HOSTNAME finish the work (6): " -e
fi


# --------------------------------------------------------------------------------------------------------
# -------------------------                     NOVA                           ---------------------------
# --------------------------------------------------------------------------------------------------------

# On all nodes --------------------
yum  install -y openstack-nova-console openstack-nova-novncproxy openstack-utils openstack-nova-api openstack-nova-conductor openstack-nova-scheduler python-cinderclient python-memcached

openstack-config --set /etc/nova/nova.conf DEFAULT memcached_servers $CON_NODE_1_IP:11211,$CON_NODE_2_IP:11211,$CON_NODE_3_IP:11211
openstack-config --set /etc/nova/nova.conf DEFAULT vncserver_proxyclient_address $NODE_IP
openstack-config --set /etc/nova/nova.conf DEFAULT vncserver_listen 0.0.0.0
openstack-config --set /etc/nova/nova.conf DEFAULT vnc_keymap es-es
openstack-config --set /etc/nova/nova.conf DEFAULT novncproxy_host $NODE_IP
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_region_name $REGION_NAME
openstack-config --set /etc/nova/nova.conf DEFAULT novncproxy_base_url http://vnc.${PUBLIC_DOMAIN}:6080/vnc_auto.html
openstack-config --set /etc/nova/nova.conf database connection mysql://nova:$IAAS_PASS@$VIP_MYSQL/nova
openstack-config --set /etc/nova/nova.conf database max_retries -1
openstack-config --set /etc/nova/nova.conf database idle_timeout 60
openstack-config --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/nova/nova.conf DEFAULT rabbit_ha_queues true
openstack-config --set /etc/nova/nova.conf DEFAULT rabbit_hosts $BE_NODE_1_IP:5672,$BE_NODE_2_IP:5672,$BE_NODE_3_IP:5672
openstack-config --set /etc/nova/nova.conf DEFAULT osapi_compute_listen $NODE_IP
openstack-config --set /etc/nova/nova.conf DEFAULT metadata_host $VIP_NOVA
openstack-config --set /etc/nova/nova.conf DEFAULT metadata_listen $NODE_IP
openstack-config --set /etc/nova/nova.conf DEFAULT metadata_listen_port 8775
openstack-config --set /etc/nova/nova.conf DEFAULT service_neutron_metadata_proxy True
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_metadata_proxy_shared_secret metatest
openstack-config --set /etc/nova/nova.conf DEFAULT glance_host $VIP_GLANCE
openstack-config --set /etc/nova/nova.conf DEFAULT network_api_class nova.network.neutronv2.api.API
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_url http://$VIP_NEUTRON:9696/
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_tenant_name services
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_username neutron
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_password $IAAS_PASS
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_auth_url http://$VIP_KEYSTONE:35357/v2.0
openstack-config --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
openstack-config --set /etc/nova/nova.conf DEFAULT libvirt_vif_driver nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
openstack-config --set /etc/nova/nova.conf conductor use_local false

# Configure Nova - Nuage integration
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_ovs_bridge alubr0
openstack-config --set /etc/nova/nova.conf DEFAULT libvirt_vif_driver nova.virt.libvirt.vif.LibvirtGenericVIFDriver
openstack-config --set /etc/nova/nova.conf DEFAULT security_group_api nova
openstack-config --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
openstack-config --set /etc/nova/nova.conf DEFAULT instance_name_template inst-%08x

# REQUIRED FOR A/A scheduler
openstack-config --set /etc/nova/nova.conf DEFAULT scheduler_host_subset_size 30
openstack-config --set /etc/nova/api-paste.ini filter:authtoken auth_host $VIP_KEYSTONE
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_tenant_name services
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_user compute
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_password $IAAS_PASS

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	# On one node only -----------------
	su nova -s /bin/sh -c "nova-manage db sync"

	pcs resource create nova-consoleauth systemd:openstack-nova-consoleauth --clone
	pcs resource create nova-novncproxy systemd:openstack-nova-novncproxy --clone
	pcs resource create nova-api systemd:openstack-nova-api --clone
	pcs resource create nova-scheduler systemd:openstack-nova-scheduler --clone
	pcs resource create nova-conductor systemd:openstack-nova-conductor --clone
	pcs constraint order start nova-consoleauth-clone then nova-novncproxy-clone
	pcs constraint colocation add nova-novncproxy-clone with nova-consoleauth-clone
	pcs constraint order start nova-novncproxy-clone then nova-api-clone
	pcs constraint colocation add nova-api-clone with nova-novncproxy-clone
	pcs constraint order start nova-api-clone then nova-scheduler-clone
	pcs constraint colocation add nova-scheduler-clone with nova-api-clone
	pcs constraint order start nova-scheduler-clone then nova-conductor-clone
	pcs constraint colocation add nova-conductor-clone with nova-scheduler-clone

	# Create firs AZ
	source /root/keystonerc_admin
	nova aggregate-create $DEFAULT_AZ $DEFAULT_AZ

        read -i "Press enter here and in $CON_NODE_2_HOSTNAME $CON_NODE_3_HOSTNAME to continue (8): " -e
else
        read -i "Press enter when $CON_NODE_1_HOSTNAME finish the work (8): " -e
fi


# --------------------------------------------------------------------------------------------------------
# -------------------------                   NEUTRON-SERVER                   ---------------------------
# --------------------------------------------------------------------------------------------------------

# On all nodes --------------------
yum install -y openstack-neutron

openstack-config --set /etc/neutron/neutron.conf DEFAULT bind_host $NODE_IP
openstack-config --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_host $VIP_KEYSTONE
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_tenant_name services
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_user neutron
openstack-config --set /etc/neutron/neutron.conf keystone_authtoken admin_password $IAAS_PASS
openstack-config --set /etc/neutron/neutron.conf database connection  mysql://neutron:$IAAS_PASS@$VIP_MYSQL:3306/ovs_neutron
openstack-config --set /etc/neutron/neutron.conf database max_retries -1
openstack-config --set /etc/neutron/neutron.conf database idle_timeout 60
openstack-config --set /etc/neutron/neutron.conf DEFAULT rabbit_ha_queues true
openstack-config --set /etc/neutron/neutron.conf DEFAULT rabbit_hosts $BE_NODE_1_IP:5672,$BE_NODE_2_IP:5672,$BE_NODE_3_IP:5672
openstack-config --set /etc/neutron/neutron.conf DEFAULT notification_driver neutron.openstack.common.notifier.rpc_notifier
openstack-config --set /etc/neutron/neutron.conf DEFAULT nova_url http://$VIP_NOVA:8774/v2
openstack-config --set /etc/neutron/neutron.conf DEFAULT nova_region_name $REGION_NAME
source /root/keystonerc_admin
openstack-config --set /etc/neutron/neutron.conf DEFAULT nova_admin_tenant_id $(keystone tenant-get services | grep id | awk '{print $4}')
openstack-config --set /etc/neutron/neutron.conf DEFAULT nova_admin_username compute
openstack-config --set /etc/neutron/neutron.conf DEFAULT nova_admin_password $IAAS_PASS
openstack-config --set /etc/neutron/neutron.conf DEFAULT nova_admin_auth_url http://$VIP_KEYSTONE:35357/v2.0
openstack-config --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes True
openstack-config --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes True
openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT auth_region $REGION_NAME
openstack-config --set /etc/neutron/neutron.conf DEFAULT service_plugins router

# Disable quotas
openstack-config --set /etc/neutron/neutron.conf quotas quota_network -1
openstack-config --set /etc/neutron/neutron.conf quotas quota_subnet -1
openstack-config --set /etc/neutron/neutron.conf quotas quota_port -1
openstack-config --set /etc/neutron/neutron.conf quotas quota_security_group -1
openstack-config --set /etc/neutron/neutron.conf quotas quota_router -1
openstack-config --set /etc/neutron/neutron.conf quotas quota_floatingip -1

# Here, atach the Nuage integration
# More info: http://docs.openstack.org/juno/config-reference/content/networking-plugin-nuage.html

# Download TGZs
cd ~
wget http://$REPO_SERVER/nuage/neutron_nuage_plugin/nuage-openstack-nuagenetlib-icehouse.tar.gz
wget http://$REPO_SERVER/nuage/neutron_nuage_plugin/nuage-openstack-neutron-icehouse-plugin.tar.gz
tar xzvf ./nuage-openstack-nuagenetlib-icehouse.tar.gz
tar xzvf ./nuage-openstack-neutron-icehouse-plugin.tar.gz

# Installing Nuage Software
cd nuagenetlib/
python setup.py install
cd ..
cd nuage-neutron-icehouse/
python setup.py install

# Remove Nuage temporary files at /root
cd ~
rm -rf ./nuage*

# Configure Neutron
openstack-config --set /etc/neutron/neutron.conf DEFAULT api_extensions_path /usr/lib/python2.7/site-packages/neutron/plugins/nuage/extensions
openstack-config --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips True
openstack-config --set /etc/neutron/neutron.conf DEFAULT core_plugin neutron.plugins.nuage.plugin_adv.NuageAdvPlugin

# Configure plugin
mkdir -p /etc/neutron/plugins/nuage
wget -O /etc/neutron/plugins/nuage/nuage_plugin.ini http://$REPO_SERVER/nuage/neutron_nuage_plugin/nuage_plugin.ini
ln -s /etc/neutron/plugins/nuage/nuage_plugin.ini /etc/neutron/plugin.ini
openstack-config --set /etc/neutron/plugins/nuage/nuage_plugin.ini DATABASE connection mysql://nuage_neutron:$IAAS_PASS@$VIP_MYSQL/nuage_neutron?charset=utf8
openstack-config --set /etc/neutron/plugins/nuage/nuage_plugin.ini KEYSTONE keystone_service_endpoint http://$VIP_KEYSTONE:35357/v2.0
openstack-config --set /etc/neutron/plugins/nuage/nuage_plugin.ini RESTPROXY server $VIP_VSD:443
openstack-config --set /etc/neutron/plugins/nuage/nuage_plugin.ini KEYSTONE keystone_admin_token $(grep ^admin_token /etc/keystone/keystone.conf |awk -F'=' '{print $2}')

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	#### On one controller only - Create neutron-server pacemaker resource
	neutron-db-manage --config-file /usr/share/neutron/neutron-dist.conf --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugin.ini stamp icehouse
	pcs resource create neutron-server systemd:neutron-server --clone
	pcs resource cleanup neutron-server


        read -i "Press enter here and in $CON_NODE_2_HOSTNAME $CON_NODE_3_HOSTNAME to continue (7): " -e
else
        read -i "Press enter when $CON_NODE_1_HOSTNAME finish the work (7): " -e
fi



# --------------------------------------------------------------------------------------------------------
# -------------------------                   CEILOMETER                       ---------------------------
# --------------------------------------------------------------------------------------------------------

# On all nodes --------------------
yum install -y openstack-ceilometer-api openstack-ceilometer-central openstack-ceilometer-collector openstack-ceilometer-common openstack-ceilometer-alarm python-ceilometer python-ceilometerclient

openstack-config --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_host $VIP_KEYSTONE
openstack-config --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_port 35357
openstack-config --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_protocol http
openstack-config --set /etc/ceilometer/ceilometer.conf keystone_authtoken admin_tenant_name services
openstack-config --set /etc/ceilometer/ceilometer.conf keystone_authtoken admin_user ceilometer
openstack-config --set /etc/ceilometer/ceilometer.conf keystone_authtoken admin_password $IAAS_PASS
openstack-config --set /etc/ceilometer/ceilometer.conf DEFAULT memcache_servers $CON_NODE_1_IP:11211,$CON_NODE_2_IP:11211,$CON_NODE_3_IP:11211
openstack-config --set /etc/ceilometer/ceilometer.conf DEFAULT rabbit_ha_queues true
openstack-config --set /etc/ceilometer/ceilometer.conf DEFAULT rabbit_hosts $BE_NODE_1_IP:5672,$BE_NODE_2_IP:5672,$BE_NODE_3_IP:5672
openstack-config --set /etc/ceilometer/ceilometer.conf publisher_rpc metering_secret $IAAS_PASS
openstack-config --set /etc/ceilometer/ceilometer.conf service_credentials os_auth_url http://$VIP_KEYSTONE:5000/v2.0
openstack-config --set /etc/ceilometer/ceilometer.conf service_credentials os_username ceilometer
openstack-config --set /etc/ceilometer/ceilometer.conf service_credentials os_tenant_name services
openstack-config --set /etc/ceilometer/ceilometer.conf service_credentials os_password $IAAS_PASS
openstack-config --set /etc/ceilometer/ceilometer.conf database connection mongodb://$BE_NODE_1_IP,$BE_NODE_2_IP,$BE_NODE_3_IP:27017/ceilometer?replicaSet=ceilometer
openstack-config --set /etc/ceilometer/ceilometer.conf database max_retries -1
openstack-config --set /etc/ceilometer/ceilometer.conf database idle_timeout 60
# We don't apply time_to_live yet, but the following command is recommended (in this example, 432000 seconds -> 5 days).
#openstack-config --set /etc/ceilometer/ceilometer.conf database time_to_live 432000
openstack-config --set /etc/ceilometer/ceilometer.conf api host $NODE_IP

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	# On one node only -----------------
	pcs resource create ceilometer-central systemd:openstack-ceilometer-central 
	pcs resource create ceilometer-collector systemd:openstack-ceilometer-collector --clone
	pcs resource create ceilometer-api systemd:openstack-ceilometer-api --clone
	pcs resource create ceilometer-delay Delay startdelay=10 --clone
	pcs resource create ceilometer-alarm-evaluator systemd:openstack-ceilometer-alarm-evaluator --clone
	pcs resource create ceilometer-alarm-notifier systemd:openstack-ceilometer-alarm-notifier --clone
	pcs resource create ceilometer-notification systemd:openstack-ceilometer-notification  --clone
	pcs constraint order start ceilometer-central then ceilometer-collector-clone
	pcs constraint order start ceilometer-collector-clone then ceilometer-api-clone
	pcs constraint order start ceilometer-api-clone then ceilometer-delay-clone
	pcs constraint order start ceilometer-delay-clone then ceilometer-alarm-evaluator-clone
	pcs constraint order start ceilometer-alarm-evaluator-clone then ceilometer-alarm-notifier-clone
	pcs constraint order start ceilometer-alarm-notifier-clone then ceilometer-notification-clone

        read -i "Press enter here and in $CON_NODE_2_HOSTNAME $CON_NODE_3_HOSTNAME to continue (9): " -e
else
        read -i "Press enter when $CON_NODE_1_HOSTNAME finish the work (9): " -e
fi


# --------------------------------------------------------------------------------------------------------
# -------------------------                     HEAT                           ---------------------------
# --------------------------------------------------------------------------------------------------------

# On all cluster nodes --------------------

# Install Software
yum install -y openstack-heat-* python-heatclient openstack-utils python-glanceclient

openstack-config --set /etc/heat/heat.conf database connection mysql://heat:$IAAS_PASS@$VIP_MYSQL/heat
openstack-config --set /etc/heat/heat.conf database max_retries -1
openstack-config --set /etc/heat/heat.conf database idle_timeout 60
openstack-config --set /etc/heat/heat.conf keystone_authtoken admin_tenant_name services
openstack-config --set /etc/heat/heat.conf keystone_authtoken admin_user heat
openstack-config --set /etc/heat/heat.conf keystone_authtoken admin_password $IAAS_PASS
openstack-config --set /etc/heat/heat.conf keystone_authtoken service_host $VIP_KEYSTONE
openstack-config --set /etc/heat/heat.conf keystone_authtoken auth_host $VIP_KEYSTONE
openstack-config --set /etc/heat/heat.conf keystone_authtoken auth_uri http://$VIP_KEYSTONE:35357/v2.0
openstack-config --set /etc/heat/heat.conf keystone_authtoken keystone_ec2_uri http://$VIP_KEYSTONE:35357/v2.0
openstack-config --set /etc/heat/heat.conf ec2authtoken auth_uri http://$VIP_KEYSTONE:5000/v2.0
openstack-config --set /etc/heat/heat.conf DEFAULT memcache_servers $CON_NODE_1_IP:11211,$CON_NODE_2_IP:11211,$CON_NODE_3_IP:11211
openstack-config --set /etc/heat/heat.conf heat_api bind_host $NODE_IP
openstack-config --set /etc/heat/heat.conf heat_api_cfn bind_host $NODE_IP
openstack-config --set /etc/heat/heat.conf heat_api_cloudwatch bind_host $NODE_IP
openstack-config --set /etc/heat/heat.conf DEFAULT heat_metadata_server_url $VIP_HEAT:8000
openstack-config --set /etc/heat/heat.conf DEFAULT heat_waitcondition_server_url $VIP_HEAT:8000/v1/waitcondition
openstack-config --set /etc/heat/heat.conf DEFAULT heat_watch_server_url $VIP_HEAT:8003
openstack-config --set /etc/heat/heat.conf DEFAULT rpc_backend heat.openstack.common.rpc.impl_kombu
openstack-config --set /etc/heat/heat.conf DEFAULT rabbit_ha_queues true
openstack-config --set /etc/heat/heat.conf DEFAULT rabbit_hosts $BE_NODE_1_IP:5672,$BE_NODE_2_IP:5672,$BE_NODE_3_IP:5672
openstack-config --set /etc/heat/heat.conf DEFAULT notification_driver heat.openstack.common.notifier.rpc_notifier

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	# On one node only -----------------

	su heat -s /bin/sh -c "heat-manage db_sync"
	pcs resource create heat-api systemd:openstack-heat-api --clone
	pcs resource create heat-api-cfn systemd:openstack-heat-api-cfn --clone
	pcs resource create heat-api-cloudwatch systemd:openstack-heat-api-cloudwatch --clone

	# IMPORTANT: heat-engine can do A/A but requires OS::Ceilometer::Alarm in templates, that means:
	# 		1) ceilometer must be working before heat
	# 		2) if somebody overrides a template can it go kaboom?
	# 		3) let´s start basic with A/P, we can easily tune it later on.

	pcs resource create heat-engine systemd:openstack-heat-engine --clone
	pcs constraint order start heat-api-clone then heat-api-cfn-clone
	pcs constraint colocation add heat-api-cfn-clone with heat-api-clone
	pcs constraint order start heat-api-cfn-clone then heat-api-cloudwatch-clone
	pcs constraint colocation add heat-api-cloudwatch-clone with heat-api-cfn-clone
	pcs constraint order start heat-api-cloudwatch-clone then heat-engine-clone
	pcs constraint colocation add heat-engine with heat-api-cloudwatch-clone

        read -i "Press enter here and in $CON_NODE_2_HOSTNAME $CON_NODE_3_HOSTNAME to continue (10): " -e
else
        read -i "Press enter when $CON_NODE_1_HOSTNAME finish the work (11): " -e
fi


# --------------------------------------------------------------------------------------------------------
# -------------------------                     HORIZON                        ---------------------------
# --------------------------------------------------------------------------------------------------------

# On all cluster nodes --------------------

# Install Software
yum install -y mod_wsgi httpd mod_ssl python-memcached openstack-dashboard

sed -i -e "s#ALLOWED_HOSTS.*#ALLOWED_HOSTS = ['*',]#g" -e "s#^CACHES#SESSION_ENGINE = 'django.contrib.sessions.backends.cache'\nCACHES#g#" -e "s#locmem.LocMemCache'#memcached.MemcachedCache',\n\t'LOCATION' : [ '${CON_NODE_1_HOSTNAME}-clu:11211', '${CON_NODE_2_HOSTNAME}-clu:11211', '${CON_NODE_3_HOSTNAME}-clu:11211', ]#g" -e 's#OPENSTACK_HOST =.*#OPENSTACK_HOST = "$VIP_KEYSTONE"#g' -e "s#^LOCAL_PATH.*#LOCAL_PATH = '/var/lib/openstack-dashboard'#g" /etc/openstack-dashboard/local_settings

# Change OPENSTACK_API_VERSION to use 3.0
cat >> /etc/openstack-dashboard/local_settings << EOF
OPENSTACK_API_VERSIONS = {
    "identity": 3
}
EOF

# Nuage-related fine-tunning of horizon
sed -e "s/'enable_quotas': True,/'enable_quotas': False,/" -i local_settings
sed -e "s/'enable_security_groups': True,/'enable_security_groups': False,/" -i local_settings

# NOTE: Enable server-status.
#	This is required by pacemaker to verify apache is responding. We only allow from localhost.
cat > /etc/httpd/conf.d/server-status.conf << EOF
<Location /server-status>
	SetHandler server-status
	Order deny,allow
	Deny from all
	Allow from localhost
</Location>
EOF

# Optional: fix apache config to listen only on a given interface (internal)
#sed -i -e 's/^Listen.*/Listen '$(ip -4 -o a | awk -v net="$INBAND_MGMT_NET" '{gsub("/[0-9]+","",$4); if ($4 ~ net) print $4}')':80/g' /etc/httpd/conf/httpd.conf 

# NOTE: horizon requires a secret key to be generated and distributed across all
#              nodes. It does not matter how you distribute it, but generation process is 
#              important.

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	# On one node only -----------------
	service httpd stop
	service httpd start
	wget http://${CON_NODE_1_HOSTNAME}-clu/dashboard -O /dev/null
	service httpd stop
	chown apache:apache /var/lib/openstack-dashboard/.secret_key_store
	rsync -Pav /var/lib/openstack-dashboard/.secret_key_store root@${CON_NODE_2_HOSTNAME}-clu:/var/lib/openstack-dashboard/
	rsync -Pav /var/lib/openstack-dashboard/.secret_key_store root@${CON_NODE_3_HOSTNAME}-clu:/var/lib/openstack-dashboard/
	pcs resource create horizon apache --clone

fi
