#!/bin/bash

. support-functions

. parameters.cfg

# Variables needed to be defined
check_vars CON_CLUSTER_NAME CON_NODE_1_HOSTNAME CON_NODE_1_IP CON_NODE_2_HOSTNAME CON_NODE_2_IP CON_NODE_3_HOSTNAME CON_NODE_3_IP VCENTER VC_USER IAAS_PASS DOMAIN

# --------------------------------------------------------------------------------------------------------
# On all cluster nodes -----------------------------------------------------------------------------------
# --------------------------------------------------------------------------------------------------------

# Install Pacemaker
yum install -y pcs pacemaker corosync fence-agents-all resource-agents openstack-selinux

# Firewall
firewall-cmd --permanent --add-service=high-availability
firewall-cmd --reload

# Enabling service
echo $IAAS_PASS | passwd --stdin hacluster
systemctl enable pcsd
systemctl start pcsd

# Authenticate nodes
pcs cluster auth ${CON_NODE_1_HOSTNAME}-clu ${CON_NODE_2_HOSTNAME}-clu ${CON_NODE_3_HOSTNAME}-clu -u hacluster -p $IAAS_PASS --force

# Add /etc/hosts lines to avoid DNS dependance
cat >> /etc/hosts << EOF
$CON_NODE_1_IP       ${CON_NODE_1_HOSTNAME}-clu.$DOMAIN          ${CON_NODE_1_HOSTNAME}-clu
$CON_NODE_2_IP       ${CON_NODE_2_HOSTNAME}-clu.$DOMAIN          ${CON_NODE_2_HOSTNAME}-clu
$CON_NODE_3_IP       ${CON_NODE_3_HOSTNAME}-clu.$DOMAIN          ${CON_NODE_3_HOSTNAME}-clu
EOF


# --------------------------------------------------------------------------------------------------------
# On one cluster node only -------------------------------------------------------------------------------
# --------------------------------------------------------------------------------------------------------

if [ "$(hostname -s)" == "$CON_NODE_1_HOSTNAME" ]; then

	# Starting the cluster
	pcs cluster setup --name $CON_CLUSTER_NAME ${CON_NODE_1_HOSTNAME}-clu ${CON_NODE_2_HOSTNAME}-clu ${CON_NODE_3_HOSTNAME}-clu
	pcs cluster enable --all
	pcs cluster start --all

	# Get UUIDs of VMs
	UUID_NODE_1=$(fence_vmware_soap -a $VCENTER -l $VC_USER -p $IAAS_PASS --ssl-insecure -z -v -o list | grep ${CON_NODE_1_HOSTNAME^^[a-z]} | awk -F, '{print $2}')
	UUID_NODE_2=$(fence_vmware_soap -a $VCENTER -l $VC_USER -p $IAAS_PASS --ssl-insecure -z -v -o list | grep ${CON_NODE_2_HOSTNAME^^[a-z]} | awk -F, '{print $2}')
	UUID_NODE_3=$(fence_vmware_soap -a $VCENTER -l $VC_USER -p $IAAS_PASS --ssl-insecure -z -v -o list | grep ${CON_NODE_3_HOSTNAME^^[a-z]} | awk -F, '{print $2}')

	# Confiugre fencing (using fence_vmware_soap)
	# How to: https://access.redhat.com/solutions/917813
	# Options: https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Fence_Configuration_Guide/s1-software-fence-vmware-soap-CA.html
	# Important: The current configuration needs SSL and SSL-INSECURE flags (to avoid certificate verification)

	pcs stonith create fence-${CON_NODE_1_HOSTNAME}-clu fence_vmware_soap ipaddr=$VCENTER ssl=1 ssl_insecure=1 login=$VC_USER passwd=$IAAS_PASS action='reboot' port=$UUID_NODE_1 pcmk_host_list=${CON_NODE_1_HOSTNAME}-clu
	pcs stonith create fence-${CON_NODE_2_HOSTNAME}-clu fence_vmware_soap ipaddr=$VCENTER ssl=1 ssl_insecure=1 login=$VC_USER passwd=$IAAS_PASS action='reboot' port=$UUID_NODE_2 pcmk_host_list=${CON_NODE_2_HOSTNAME}-clu
	pcs stonith create fence-${CON_NODE_3_HOSTNAME}-clu fence_vmware_soap ipaddr=$VCENTER ssl=1 ssl_insecure=1 login=$VC_USER passwd=$IAAS_PASS action='reboot' port=$UUID_NODE_3 pcmk_host_list=${CON_NODE_3_HOSTNAME}-clu

	# Check the status of fencing devices
	pcs stonith show --full
	pcs status

fi
