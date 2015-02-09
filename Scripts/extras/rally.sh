#!/bin/bash

. support-functions

. parameters.cfg

# Variables needed to be defined
check_vars IAAS_PASS REGION_NAME PROXY CONFIG_FILE VIP_KEYSTONE

# Rally installation script
# Info: https://wiki.openstack.org/wiki/Rally

# Create user osp-test with sudo NOPASSWD
useradd osp-test
echo "$IAAS_PASS" | passwd --stdin osp-test
echo "osp-test    ALL=(ALL)       NOPASSWD:ALL" >> /etc/sudoers

# Install Git utils and prepare Git environment
yum install -y git

# Cloning Rally Git repo
su - osp-test
git config --global http.proxy http://$PROXY
git config --global https.proxy http://$PROXY
git clone https://git.openstack.org/stackforge/rally

# Installing rally with user osp-test and sudo (preserving environment variables with -E)
export http_proxy=http://$PROXY
export https_proxy=http://$PROXY
sudo -E ./rally/install_rally.sh

# Configuring Rally
cat > $CONFIG_FILE << EOF
{
    "type": "ExistingCloud",
    "auth_url": "http://$VIP_KEYSTONE:5000/v2.0/",
    "region_name": "$REGION_NAME",
    "endpoint_type": "public",
    "admin": {
        "username": "admin",
        "password": "$IAAS_PASS",
        "tenant_name": "admin",
    }
}
EOF
rally deployment create --filename=$CONFIG_FILE --name=$REGION_NAME
exit

# Deleting 'sudo without password' feature for user osp-test
sed -i '/osp-test    ALL=(ALL)       NOPASSWD:ALL/d' /etc/sudoers

# NOTE: https://wiki.openstack.org/wiki/Rally/HowTo
# For example:
#    $ rally use deployment --name=boaw
#    $ rally deployment check

