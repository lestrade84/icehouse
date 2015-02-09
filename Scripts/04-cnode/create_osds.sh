#!/bin/bash

# To be executed on ceph-admin node

if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters. You must provided the OSD host name."
    exit 1
fi

HOST=$1

ceph-deploy osd create $HOST:/dev/sda:/dev/sdo5
ceph-deploy osd create $HOST:/dev/sdb:/dev/sdo6
ceph-deploy osd create $HOST:/dev/sdc:/dev/sdo7
ceph-deploy osd create $HOST:/dev/sdd:/dev/sdo8
ceph-deploy osd create $HOST:/dev/sde:/dev/sdo9
ceph-deploy osd create $HOST:/dev/sdf:/dev/sdp5
ceph-deploy osd create $HOST:/dev/sdg:/dev/sdp6
ceph-deploy osd create $HOST:/dev/sdh:/dev/sdp7
ceph-deploy osd create $HOST:/dev/sdi:/dev/sdp8
ceph-deploy osd create $HOST:/dev/sdj:/dev/sdp9
