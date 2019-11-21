#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# this script is called to initialize bastion host when it is created
source ./env.sh

echo "update os packages"
sudo apt update
sudo apt-get -y install kubectl
sudo apt-get -y install git
sudo apt-get -y install nfs-common

mnt_point=mnt/share
echo "mount Filestore from ${STORE_IP} to /${mnt_point}"
sudo mkdir /${mnt_point}
sudo mount ${STORE_IP}:/vol1 /${mnt_point}
sudo chmod go+rw /${mnt_point}

echo "checkout fabri-operation repo"
git clone https://github.com/yxuco/fabric-operation.git
sed -i -e "s|^GKE_MOUNT_POINT=.*|GKE_MOUNT_POINT=${mnt_point}|" ./fabric-operation/config/setup.sh
sed -i -e "s|^GKE_STORE_IP=.*|GKE_STORE_IP=${STORE_IP}|" ./fabric-operation/config/setup.sh
