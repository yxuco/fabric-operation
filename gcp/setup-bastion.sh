#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# Execute this script on bastion host to initialize the host
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
sed -i -e "s|^MOUNT_POINT=.*|MOUNT_POINT=${mnt_point}|" ./fabric-operation/config/setup.sh
sed -i -e "s|^GCP_STORE_IP=.*|GCP_STORE_IP=${STORE_IP}|" ./fabric-operation/config/setup.sh

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
