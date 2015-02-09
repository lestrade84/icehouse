#!/bin/bash

. support-functions

. parameters.cfg

# Variables needed to be defined
check_vars REGION_NAME DOMAIN PUBLIC_DOMAIN IAAS_PASS OS_CTL_NET INBAND_MGMT_NET VIP_HORIZON VIP_MYSQL VIP_KEYSTONE VIP_GLANCE VIP_CINDER VIP_SWIFT VIP_NEUTRON VIP_NOVA VIP_HEAT VIP_MONGO VIP_CEILOMETER VIP_LDAP REPO_SERVER CON_NODE_1_IP CON_NODE_2_IP CON_NODE_3_IP BE_NODE_1_IP BE_NODE_2_IP BE_NODE_3_IP SDN_NET NUAGE_ACTIVE_CONTROLLER NUAGE_STANDBY_CONTROLLER PV_1 PV_2 PV_3 PV_4 VG_NAME LV_NAME LV_NOVA_MOUNT_DIR CINDER_VOLUME_UUID NOVA_12_NIC ROOT_HOME NOVA_HOME

# --------------------------------------------------------------------------------------------------------
# -------------------------                       PRE-REQUISITES               ---------------------------
# --------------------------------------------------------------------------------------------------------


# Create volume group and logical volume for ephimeral local storage (nova)
vgcreate VG_nova /dev/sdk /dev/sdl /dev/sdm /dev/sdn
lvcreate --type raid10 --nosync -l 100%VG -i 2 -m 1 -n nova VG_nova
mkfs.xfs /dev/mapper/VG_nova-nova

# Mounting this LV at boot time
mkdir -p /var/lib/nova
echo "/dev/mapper/VG_nova-nova /var/lib/nova                      xfs     defaults        0 0" >> /etc/fstab
mount -a


# Configuring RED HAT repos
cat > /etc/yum.repos.d/local.repo << EOF_REPO_LOCAL
[rhel-7-server-openstack-5.0-rpms]
name=Red Hat OpenStack Platform 5 - local packages for 
baseurl=http://$REPO_SERVER/repos/rhel-7-server-openstack-5.0-rpms/
enabled=1
gpgcheck=0

[rhel-7-server-rpms]
name=Red Hat Enterprise Linux 7 - local packages for 
baseurl=http://$REPO_SERVER/repos/rhel-7-server-rpms/
enabled=1
gpgcheck=0

[rhel-7-server-rh-common-rpms]
name=Red Hat Enterpsie Linux Common - local packages for 
baseurl=http://$REPO_SERVER/repos/rhel-7-server-rh-common-rpms/
enabled=1
gpgcheck=0

[rhel-server-rhscl-7-rpms]
name=Red Hat Software Collections - local packages for 
baseurl=http://$REPO_SERVER/repos/rhel-server-rhscl-7-rpms/
enabled=1
gpgcheck=0

[rhel-ha-for-rhel-7-server-rpms]
name=Red Hat Enterpsie Linux High Availability - local packages for 
baseurl=http://$REPO_SERVER/repos/rhel-ha-for-rhel-7-server-rpms/
enabled=1
gpgcheck=0

[rhel-7-server-optional-rpms]
name=Red Hat Enterprise Linux 7 - optional forNODE_3_NAME
baseurl=http://$REPO_SERVER/repos/rhel-7-server-optional-rpms/
enabled=1
gpgcheck=0
EOF_REPO_LOCAL


# Configuring NUAGE repos
cat > /etc/yum.repos.d/rhel-7-nuage-vrs-rpms.repo << EOF_NUAGE_REPO
[rhel-7-nuage-vrs-rpms]
name=Nuage VRS Software
baseurl=http://$REPO_SERVER/repos/nuage-vrs/
enabled=1
gpgcheck=0
EOF_NUAGE_REPO




# --------------------------------------------------------------------------------------------------------
# -------------------------                       NOVA                         ---------------------------
# --------------------------------------------------------------------------------------------------------

# Installing required software
yum install -y openstack-nova-compute openstack-utils python-cinder openstack-ceilometer-compute python-twisted-core perl-JSON vconfig nuage-openvswitch nuage-metadata-agent

# Enable default services
systemctl enable libvirtd
systemctl start libvirtd
virsh net-destroy default
virsh net-undefine default

# Configuring nova.conf
openstack-config --set /etc/nova/nova.conf DEFAULT memcached_servers $CON_NODE_1_IP:11211,$CON_NODE_2_IP:11211,$CON_NODE_3_IP:11211
openstack-config --set /etc/nova/nova.conf DEFAULT vncserver_proxyclient_address $(ip addr show dev ${NOVA_12_NIC} scope global | grep inet | sed -e 's#.*inet ##g' -e 's#/.*##g')
openstack-config --set /etc/nova/nova.conf DEFAULT vncserver_listen 0.0.0.0
openstack-config --set /etc/nova/nova.conf DEFAULT novncproxy_host $(ip addr show dev $NOVA_12_NIC scope global | grep inet | sed -e 's#.*inet ##g' -e 's#/.*##g')
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_region_name $REGION_NAME
openstack-config --set /etc/nova/nova.conf DEFAULT novncproxy_base_url http://vnc.${PUBLIC_DOMAIN}:6080/vnc_auto.html
openstack-config --set /etc/nova/nova.conf database connection mysql://nova:${IAAS_PASS}@${VIP_MYSQL}/nova
openstack-config --set /etc/nova/nova.conf database max_retries -1
openstack-config --set /etc/nova/nova.conf database idle_timeout 60
openstack-config --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
openstack-config --set /etc/nova/nova.conf DEFAULT rabbit_ha_queues true
openstack-config --set /etc/nova/nova.conf DEFAULT rabbit_hosts $BE_NODE_1_IP:5672,$BE_NODE_2_IP:5672,$BE_NODE_3_IP:5672
openstack-config --set /etc/nova/nova.conf DEFAULT metadata_host $VIP_NOVA
openstack-config --set /etc/nova/nova.conf DEFAULT metadata_listen $(ip addr show dev $NOVA_12_NIC scope global | grep inet | sed -e 's#.*inet ##g' -e 's#/.*##g')
openstack-config --set /etc/nova/nova.conf DEFAULT metadata_listen_port 8775
openstack-config --set /etc/nova/nova.conf DEFAULT service_neutron_metadata_proxy True
openstack-config --set /etc/nova/nova.conf DEFAULT use_forwarded_for True
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_metadata_proxy_shared_secret metatest
openstack-config --set /etc/nova/nova.conf DEFAULT glance_host $VIP_GLANCE
openstack-config --set /etc/nova/nova.conf DEFAULT network_api_class nova.network.neutronv2.api.API
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_url http://$VIP_NEUTRON:9696/
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_tenant_name services
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_username neutron
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_password $IAAS_PASS
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_admin_auth_url http://$VIP_KEYSTONE:35357/v2.0
openstack-config --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
openstack-config --set /etc/nova/nova.conf DEFAULT neutron_ovs_bridge alubr0
openstack-config --set /etc/nova/nova.conf DEFAULT libvirt_vif_driver nova.virt.libvirt.vif.LibvirtGenericVIFDriver
openstack-config --set /etc/nova/nova.conf DEFAULT security_group_api nova
openstack-config --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
openstack-config --set /etc/nova/nova.conf DEFAULT instance_name_template inst-%08x
openstack-config --set /etc/nova/nova.conf conductor use_local false

# For Live Migration
openstack-config --set /etc/nova/nova.conf libvirt live_migration_flag VIR_MIGRATE_UNDEFINE_SOURCE,VIR_MIGRATE_PEER2PEER,VIR_MIGRATE_LIVE,VIR_MIGRATE_TUNNELLED
openstack-config --set /etc/nova/nova.conf libvirt live_migration_uri qemu+ssh://nova@%s/system

# Assign bash to nova user
usermod -s /bin/bash nova

# Configure SSH-KEY sharing for computes 'root' -> 'nova'
mkdir -p $ROOT_HOME/.ssh/
wget -O $ROOT_HOME/.ssh/id_rsa http://$REPO_SERVER/utils/ssh-live-migration/id_rsa
chmod 600 $ROOT_HOME/.ssh/id_rsa
echo "StrictHostKeyChecking=no" > $ROOT_HOME/.ssh/config
chmod 400 $ROOT_HOME/.ssh/config

# Configure Authorized_Keys for nova user (his home directory is /var/lib/nova)
mkdir -p $NOVA_HOME/.ssh/
chown nova:nova $NOVA_HOME/.ssh/
chmod 700 $NOVA_HOME/.ssh/
wget -O $NOVA_HOME/.ssh/authorized_keys http://$REPO_SERVER/utils/ssh-live-migration/authorized_keys
chmod 600 $NOVA_HOME/.ssh/authorized_keys

# Configure Authorized_Keys for nova user (his home directory is /var/lib/nova)
echo "StrictHostKeyChecking=no" > $NOVA_HOME/.ssh/config
chmod 400 $NOVA_HOME/.ssh/config
wget -O $NOVA_HOME/.ssh/id_rsa http://$REPO_SERVER/utils/ssh-live-migration/id_rsa_nova
chmod 600 $NOVA_HOME/.ssh/id_rsa
chown -R nova:nova $NOVA_HOME/.ssh

# Configure nova to restart after reboot hypervisors
openstack-config --set /etc/nova/nova.conf DEFAULT resume_guests_state_on_host_boot true

# REQUIRED FOR A/A scheduler
openstack-config --set /etc/nova/nova.conf DEFAULT scheduler_host_subset_size 30
openstack-config --set /etc/nova/api-paste.ini filter:authtoken auth_host $VIP_KEYSTONE
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_tenant_name services
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_user compute
openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_password $IAAS_PASS

# Nova integration with Ceilometer
openstack-config --set /etc/nova/nova.conf DEFAULT instance_usage_audit True
openstack-config --set /etc/nova/nova.conf DEFAULT instance_usage_audit_period hour
openstack-config --set /etc/nova/nova.conf DEFAULT notify_on_state_change vm_and_task_state
openstack-config --set /etc/nova/nova.conf DEFAULT notification_driver nova.openstack.common.notifier.rpc_notifier
sed  -i -e  's#nova.openstack.common.notifier.rpc_notifier#nova.openstack.common.notifier.rpc_notifier\nnotification_driver  = ceilometer.compute.nova_notifier#g' /etc/nova/nova.conf

# Required for Ceilometer
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
# openstack-config --set /etc/ceilometer/ceilometer.conf database time_to_live 432000
openstack-config --set /etc/ceilometer/ceilometer.conf api host $(ip addr show dev $NOVA_12_NIC scope global | grep inet | sed -e 's#.*inet ##g' -e 's#/.*##g')



# --------------------------------------------------------------------------------------------------------
# -------------------------                       NUAGE                        ---------------------------
# --------------------------------------------------------------------------------------------------------

# Configure Nuage config files
echo "PERSONALITY=vrs" >> /etc/default/openvswitch
echo "PLATFORM=kvm" >> /etc/default/openvswitch
echo "DEFAULT_BRIDGE=alubr0" >> /etc/default/openvswitch
echo "CONN_TYPE=tcp" >> /etc/default/openvswitch
echo "ACTIVE_CONTROLLER=$NUAGE_ACTIVE_CONTROLLER" >> /etc/default/openvswitch
echo "STANDBY_CONTROLLER=$NUAGE_STANDBY_CONTROLLER" >> /etc/default/openvswitch

# Configuring Nuage Metadata Agent
echo "METADATA_PORT=9697" >> /etc/default/nuage-metadata-agent
echo "NOVA_METADATA_IP=$VIP_NOVA" >> /etc/default/nuage-metadata-agent
echo "NOVA_METADATA_PORT=8775" >> /etc/default/nuage-metadata-agent
echo "METADATA_PROXY_SHARED_SECRET=metatest" >> /etc/default/nuage-metadata-agent
echo "NOVA_CLIENT_VERSION=2" >> /etc/default/nuage-metadata-agent
echo "NOVA_OS_USERNAME=compute" >> /etc/default/nuage-metadata-agent
echo "NOVA_OS_PASSWORD=$IAAS_PASS" >> /etc/default/nuage-metadata-agent
echo "NOVA_OS_TENANT_NAME=services" >> /etc/default/nuage-metadata-agent
echo "NOVA_OS_AUTH_URL=http://$VIP_KEYSTONE:5000/v2.0" >> /etc/default/nuage-metadata-agent
echo "NUAGE_METADATA_AGENT_START_WITH_OVS=false" >> /etc/default/nuage-metadata-agent
echo "NOVA_API_ENDPOINT_TYPE=publicURL" >> /etc/default/nuage-metadata-agent

# Enable and start required services
systemctl enable openstack-nova-compute
systemctl restart openstack-nova-compute
systemctl enable openstack-ceilometer-compute
systemctl restart openstack-ceilometer-compute
systemctl enable nuage-metadata-agent
systemctl restart nuage-metadata-agent
systemctl enable openvswitch
systemctl restart openvswitch



# --------------------------------------------------------------------------------------------------------
# -------------------------                       CEPH                         ---------------------------
# --------------------------------------------------------------------------------------------------------

# First, install ceph software from ceph-admin node

# Then, execute the following commands:

wget http://$REPO_SERVER/utils/cinder-volume-keys/secret.xml
wget http://$REPO_SERVER/utils/cinder-volume-keys/client.volumes.key
virsh secret-define --file ~/secret.xml
virsh secret-set-value --secret $CINDER_VOLUME_UUID --base64 $(cat ~/client.volumes.key)
rm -f ~/secret.xml ~/client.volumes.key
openstack-config --set /etc/nova/nova.conf libvirt libvirt_images_type rbd 
openstack-config --set /etc/nova/nova.conf libvirt libvirt_images_rbd_pool volumes 
openstack-config --set /etc/nova/nova.conf libvirt libvirt_images_rbd_ceph_conf /etc/ceph/ceph.conf 
openstack-config --set /etc/nova/nova.conf libvirt libvirt_inject_password false 
openstack-config --set /etc/nova/nova.conf libvirt libvirt_inject_key false 
openstack-config --set /etc/nova/nova.conf libvirt libvirt_inject_partition -2 
systemctl restart openstack-nova-compute
