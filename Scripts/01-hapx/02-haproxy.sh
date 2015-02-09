#!/bin/bash

. support-functions

. parameters.cfg

# Variables needed to be defined
check_vars HA_NODE_1_HOSTNAME HA_NODE_1_IP HA_NODE_2_HOSTNAME HA_NODE_2_IP HA_NODE_3_HOSTNAME HA_NODE_3_IP IAAS_PASS DOMAIN PUBLIC_DOMAIN OS_CTL_NET INBAND_MGMT_NET NUAGE_VSD_1 NUAGE_VSD_1_IP NUAGE_VSD_2 NUAGE_VSD_2_IP NUAGE_VSD_3 NUAGE_VSD_3_IP VIP_HORIZON VIP_NUAGE VIP_MYSQL VIP_KEYSTONE VIP_GLANCE VIP_CINDER VIP_SWIFT VIP_NEUTRON VIP_NOVA VIP_HEAT VIP_MONGO VIP_CEILOMETER VIP_LDAP LDAP_NODE LDAP_NODE_IP CON_NODE_1_IP CON_NODE_2_IP CON_NODE_3_IP BE_NODE_1_IP BE_NODE_2_IP BE_NODE_3_IP HORIZON_NODE_1_INBAND HORIZON_NODE_2_INBAND HORIZON_NODE_3_INBAND HORIZON_CN

# --------------------------------------------------------------------------------------------------------
# On all cluster nodes -----------------------------------------------------------------------------------
# --------------------------------------------------------------------------------------------------------

# Installing HAproxy software
yum install -y haproxy

# Network metering...
echo "net.ipv4.ip_nonlocal_bind=1" >> /etc/sysctl.d/haproxy.conf
sysctl net.ipv4.ip_nonlocal_bind=1

cat >/etc/sysctl.d/tcp_keepalive.conf << EOF
net.ipv4.tcp_keepalive_intvl = 1
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_time = 5
EOF
sysctl net.ipv4.tcp_keepalive_intvl=1
sysctl net.ipv4.tcp_keepalive_probes=5
sysctl net.ipv4.tcp_keepalive_time=5

# Creating self-signed certificate for Horizon https -- only in one node
openssl req -new -x509 -days 3650 -nodes -keyout horizon.key -out horizon.crt -subj "/C=ES/ST=Madrid/L=Torrelodones/O=Spitzer Inc./OU=IT/CN=${HORIZON_CN}"
cat horizon.crt horizon.key > horizon.pem
chmod u-w horizon.pem
cp horizon.pem /etc/ssl/certs/horizon.pem
rm -f horizon.*
rsync -Pav /etc/ssl/certs/horizon.pem $HA_NODE_2_HOSTNAME:/etc/ssl/certs/
rsync -Pav /etc/ssl/certs/horizon.pem $HA_NODE_3_HOSTNAME:/etc/ssl/certs/


# Parsing and creating haproxy.cfg config file
cat > /etc/haproxy/haproxy.cfg << EOF
global
    daemon
    tune.ssl.default-dh-param 2048
defaults
    mode tcp
    maxconn 15000
    option  tcplog
    option  redispatch
    retries  3
    timeout connect 5s
    timeout client 30s
    timeout server 30s

frontend vip-db
    bind $VIP_MYSQL:3306
    timeout client 90s
    default_backend db-vms-galera
backend db-vms-galera
    option httpchk
    stick-table type ip size 2
    stick on dst
    timeout server 90s
    server ${BE_NODE_1_HOSTNAME}-oscp $BE_NODE_1_IP:3306 check inter 1s port 9200
    server ${BE_NODE_2_HOSTNAME}-oscp $BE_NODE_2_IP:3306 check inter 1s port 9200
    server ${BE_NODE_3_HOSTNAME}-oscp $BE_NODE_3_IP:3306 check inter 1s port 9200

frontend vip-keystone-admin
    bind $VIP_KEYSTONE:35357
    default_backend keystone-admin-vms
    timeout client 60s
backend keystone-admin-vms
    balance roundrobin
    timeout server 600s
    timeout connect 5s
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:35357 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:35357 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:35357 check inter 1s

frontend vip-keystone-public
    bind $VIP_KEYSTONE:5000
    default_backend keystone-public-vms
    timeout client 60s
backend keystone-public-vms
    balance roundrobin
    timeout server 600s
    timeout connect 5s
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:5000 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:5000 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:5000 check inter 1s

frontend  vip-glance-api
    bind $VIP_GLANCE:9191
    default_backend glance-api-vms
backend glance-api-vms
    balance roundrobin
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:9191 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:9191 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:9191 check inter 1s

frontend vip-glance-registry
    bind $VIP_GLANCE:9292
    default_backend glance-registry-vms
backend glance-registry-vms
    balance roundrobin
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:9292 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:9292 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:9292 check inter 1s

frontend vip-cinder
    bind $VIP_CINDER:8776
    default_backend cinder-vms
backend cinder-vms
    balance roundrobin
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:8776 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:8776 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:8776 check inter 1s

frontend vip-swift
    bind $VIP_SWIFT:8080
    default_backend swift-vms
backend swift-vms
    balance roundrobin
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:8080 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:8080 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:8080 check inter 1s

frontend vip-neutron
    bind $VIP_NEUTRON:9696
    default_backend neutron-vms
backend neutron-vms
    balance roundrobin
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:9696 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:9696 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:9696 check inter 1s

frontend vip-nova-vnc-novncproxy
    bind $VIP_NOVA:6080
    default_backend nova-vnc-novncproxy-vms
backend nova-vnc-novncproxy-vms
    balance roundrobin
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:6080 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:6080 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:6080 check inter 1s

frontend vip-nova-metadata
    bind $VIP_NOVA:8775
    default_backend nova-metadata-vms
backend nova-metadata-vms
    balance roundrobin
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:8775 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:8775 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:8775 check inter 1s

frontend vip-nova-api
    bind $VIP_NOVA:8774
    default_backend nova-api-vms
backend nova-api-vms
    balance roundrobin
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:8774 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:8774 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:8774 check inter 1s

frontend vip-horizon
    bind $VIP_HORIZON:80
    bind $VIP_HORIZON:443 ssl crt /etc/ssl/certs/horizon.pem
    timeout client 180s
    reqadd X-Forwarded-Proto:\ https
    default_backend horizon-vms
backend horizon-vms
    balance roundrobin
    timeout server 180s
    mode http
    cookie SERVERID insert indirect nocache
    server ${CON_NODE_1_HOSTNAME}-oscp $HORIZON_NODE_1_INBAND:80 check inter 1s cookie $HORIZON_NODE_1_INBAND
    server ${CON_NODE_2_HOSTNAME}-oscp $HORIZON_NODE_2_INBAND:80 check inter 1s cookie $HORIZON_NODE_2_INBAND
    server ${CON_NODE_3_HOSTNAME}-oscp $HORIZON_NODE_3_INBAND:80 check inter 1s cookie $HORIZON_NODE_3_INBAND
    redirect scheme https if !{ ssl_fc }

frontend vip-heat-cfn
    bind $VIP_HEAT:8000
    default_backend heat-cfn-vms
backend heat-cfn-vms
    balance roundrobin
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:8000 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:8000 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:8000 check inter 1s

frontend vip-heat-cloudw
    bind $VIP_HEAT:8003
    default_backend heat-cloudw-vms
backend heat-cloudw-vms
    balance roundrobin
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:8003 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:8003 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:8003 check inter 1s

frontend vip-heat-srv
    bind $VIP_HEAT:8004
    default_backend heat-srv-vms
backend heat-srv-vms
    balance roundrobin
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:8004 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:8004 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:8004 check inter 1s

frontend vip-ceilometer
    bind $VIP_CEILOMETER:8777
    timeout client 90s
    default_backend ceilometer-vms
backend ceilometer-vms
    balance roundrobin
    timeout server 90s
    server ${CON_NODE_1_HOSTNAME}-oscp $CON_NODE_1_IP:8777 check inter 1s
    server ${CON_NODE_2_HOSTNAME}-oscp $CON_NODE_2_IP:8777 check inter 1s
    server ${CON_NODE_3_HOSTNAME}-oscp $CON_NODE_3_IP:8777 check inter 1s

frontend vip-ldap
    bind $VIP_LDAP:389
    timeout client 90s
    default_backend ldap-vms
backend ldap-vms
    balance roundrobin
    timeout server 90s
    server $LDAP_NODE $LDAP_NODE_IP:389 check inter 1s

frontend vip-ldaps
    bind $VIP_LDAP:636
    timeout client 90s
    default_backend ldaps-vms
backend ldaps-vms
    balance roundrobin
    timeout server 90s
    server $LDAP_NODE $LDAP_NODE_IP:636 check inter 1s

frontend nuage-main
    bind $VIP_NUAGE:443
    timeout http-request    10s
    timeout http-keep-alive 10s
    timeout client          1m
    maxconn                 3000
    default_backend nuage-vsd-main
backend nuage-vsd-main
    mode tcp
    balance source
    option                  redispatch
    retries                 3
    timeout queue           1m
    timeout connect         10s
    timeout check           10s
    timeout server          1m
    server $NUAGE_VSD_1 $NUAGE_VSD_1_IP:8443 check inter 1s
    server $NUAGE_VSD_2 $NUAGE_VSD_2_IP:8443 check inter 1s
    server $NUAGE_VSD_3 $NUAGE_VSD_3_IP:8443 check inter 1s

frontend nuage-stats
    bind $VIP_NUAGE:4242
    timeout http-request    10s
    timeout http-keep-alive 10s
    timeout client          1m
    maxconn                 3000
    default_backend nuage-vsd-stats
backend nuage-vsd-stats
    mode tcp
    balance source
    option                  redispatch
    retries                 3
    timeout queue           1m
    timeout connect         10s
    timeout check           10s
    timeout server          1m
    server $NUAGE_VSD_1 $NUAGE_VSD_1_IP:4242 check inter 1s
    server $NUAGE_VSD_2 $NUAGE_VSD_2_IP:4242 check inter 1s
    server $NUAGE_VSD_3 $NUAGE_VSD_3_IP:4242 check inter 1s


listen stats :1936
    mode http
    stats enable
    stats hide-version
    stats realm Haproxy\ Statistics
    stats uri /
    stats auth admin:$IAAS_PASS


EOF



# --------------------------------------------------------------------------------------------------------
# On one cluster node only -------------------------------------------------------------------------------
# --------------------------------------------------------------------------------------------------------

if [ "$(hostname -s)" == "$HA_NODE_1_HOSTNAME" ]; then

	pcs resource create lb-haproxy systemd:haproxy --clone
	pcs resource create vip-db IPaddr2 ip=$VIP_MYSQL
	pcs resource create vip-keystone IPaddr2 ip=$VIP_KEYSTONE
	pcs resource create vip-glance IPaddr2 ip=$VIP_GLANCE
	pcs resource create vip-cinder IPaddr2 ip=$VIP_CINDER
	pcs resource create vip-swift IPaddr2 ip=$VIP_SWIFT
	pcs resource create vip-neutron IPaddr2 ip=$VIP_NEUTRON
	pcs resource create vip-nova IPaddr2 ip=$VIP_NOVA
	pcs resource create vip-horizon IPaddr2 ip=$VIP_HORIZON
	pcs resource create vip-heat IPaddr2 ip=$VIP_HEAT
	pcs resource create vip-ceilometer IPaddr2 ip=$VIP_CEILOMETER
	pcs resource create vip-ldap IPaddr2 ip=$VIP_LDAP
	pcs resource create vip-nuage IPaddr2 ip=$VIP_NUAGE

fi
