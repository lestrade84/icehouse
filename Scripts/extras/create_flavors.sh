#!/bin/bash

source ~/keystonerc_admin

# Creating flavors
nova flavor-create --is-public true prb.xsmall 001 2048 60 1
nova flavor-create --is-public true prb.small 002 4096 60 2
nova flavor-create --is-public true prb.medium 003 8192 60 4
nova flavor-create --is-public true prb.large 004 16384 60 4
nova flavor-create --is-public true prb.xlarge1 005 32678 60 8
nova flavor-create --is-public true prb.xlarge2 006 65536 60 8
nova flavor-create --is-public true prb.xxlarge1 007 131072 60 16
nova flavor-create --is-public true prb.xxlarge2 008 196608 60 16
