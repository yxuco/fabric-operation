#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# Execute this script on bastion host to initialize the host
source ./env.sh

sudo apt-get update

# install kubectl
sudo snap install kubectl --classic

# setup working files
mkdir -p .kube
if [ -f "config.yaml" ]; then
  mv config.yaml .kube/config
fi
mkdir -p .azure
echo "STORAGE_ACCT=${STORAGE_ACCT}" > .azure/store-secret
echo "STORAGE_KEY=${STORAGE_KEY}" >> .azure/store-secret

mnt_point=mnt/share

# download fabric operation project
git clone https://github.com/yxuco/fabric-operation.git
sed -i -e "s|^MOUNT_POINT=.*|MOUNT_POINT=${mnt_point}|" ./fabric-operation/config/setup.sh
sed -i -e "s|^AZ_STORAGE_SHARE=.*|AZ_STORAGE_SHARE=${STORAGE_SHARE}|" ./fabric-operation/config/setup.sh

# mount Azure file
sudo mkdir -p /${mnt_point}

sudo mkdir -p /etc/smbcredentials
cred=/etc/smbcredentials/${STORAGE_ACCT}.cred
echo "username=${STORAGE_ACCT}" | sudo tee ${cred} > /dev/null
echo "password=${STORAGE_KEY}" | sudo tee -a ${cred} > /dev/null
sudo chmod 600 ${cred}
check=$(grep "${SMB_PATH} /${mnt_point}" /etc/fstab)
if [ ! -z "${check}" ]; then
  echo "skip update of /etc/fstab to avoid mount conflict"
else
  echo "${SMB_PATH} /${mnt_point} cifs nofail,vers=3.0,credentials=${cred},serverino" | sudo tee -a /etc/fstab > /dev/null
fi
sudo mount -a

# setup for building cient service
echo "install protobuf 3.7.1"
sudo apt-get install unzip
PROTOC_ZIP=protoc-3.7.1-linux-x86_64.zip
curl -OL https://github.com/protocolbuffers/protobuf/releases/download/v3.7.1/$PROTOC_ZIP
sudo unzip -o $PROTOC_ZIP -d /usr/local bin/protoc
sudo unzip -o $PROTOC_ZIP -d /usr/local 'include/*'
rm -f $PROTOC_ZIP

echo "install Golang 1.12.14"
GO_ZIP=go1.12.14.linux-amd64.tar.gz
curl -O https://storage.googleapis.com/golang/$GO_ZIP
sudo tar -xf $GO_ZIP -C /usr/local
mkdir -p ~/go/{bin,pkg,src}
echo "export GOPATH=$HOME/go" >> .profile
echo "export PATH=$HOME/go/bin:/usr/local/go/bin:$PATH" >> .profile
rm -f $GO_ZIP

echo "install grpc gateway Go packages"
. .profile
go get -u github.com/golang/protobuf/protoc-gen-go
go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway
go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger

sudo apt install make

# setup for dovetail
echo "install jq and gcc"
sudo apt -y install build-essential
curl -OL https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
chmod +x jq-linux64
sudo mv jq-linux64 /usr/local/bin/jq

# utility to merge yaml files, e.g., 'yq m file1 file2'
curl -OL https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_amd64
chmod +x yq_linux_amd64
sudo mv yq_linux_amd64 /usr/local/yq

echo "setup dovetail"
git clone https://github.com/TIBCOSoftware/dovetail-contrib.git
go get -u github.com/project-flogo/cli/...

# install fabric binary for chaincode packaging
curl -sSL http://bit.ly/2ysbOFE | bash -s -- 1.4.4 1.4.4 0.4.18
