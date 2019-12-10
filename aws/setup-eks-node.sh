#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# Execute this script on bastion host to configure bastion host, and
# install amazon-efs-utils on a specified EKS nodes, or all EKS nodes if no node is specified
# usage: ./setup-eks-node.sh [ host [ host ] ]

cd "$( dirname "${BASH_SOURCE[0]}" )"
source ./env.sh

echo "setup AWS and Kubernetes environment"
mkdir -p .aws
mv config .aws
mv credentials .aws
mkdir -p .kube
mv config.yaml .kube/config

echo "mount EFS volume ${EFS_SERVER} to /${MOUNT_POINT}"
sudo mount -t nfs4 -o nfsvers=4.1 ${EFS_SERVER}:/ /${MOUNT_POINT}

if [ "$#" -eq 0 ]; then
  region=$(aws configure get region)
  nodeHosts=$(aws ec2 describe-instances --region ${region} --query 'Reservations[*].Instances[*].PublicDnsName' --output text --filters "Name=tag:Name,Values=${EKS_STACK}-ng-*-Node" "Name=instance-state-name,Values=running")
  array=( ${nodeHosts} )
else
  array=( "$@" )
fi

for s in "${array[@]}"; do
echo "install amazon-efs-utils on host ${s}"
ssh -i /home/ec2-user/.ssh/${SSH_PRIVKEY} -o "StrictHostKeyChecking no" ec2-user@${s} << EOF
  sudo yum -y update
  sudo yum -y install amazon-efs-utils
EOF
done

echo "install EFS csi driver"
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"

echo "download fabric-operation project and set filesystem id ${AWS_FSID}"
git clone https://github.com/yxuco/fabric-operation.git
sed -i -e "s|^MOUNT_POINT=.*|MOUNT_POINT=${MOUNT_POINT}|" ./fabric-operation/config/setup.sh
sed -i -e "s|^AWS_FSID=.*|AWS_FSID=${AWS_FSID}|" ./fabric-operation/config/setup.sh

echo "install protobuf 3.7.1"
PROTOC_ZIP=protoc-3.7.1-linux-x86_64.zip
curl -OL https://github.com/protocolbuffers/protobuf/releases/download/v3.7.1/$PROTOC_ZIP
sudo unzip -o $PROTOC_ZIP -d /usr/local bin/protoc
sudo unzip -o $PROTOC_ZIP -d /usr/local 'include/*'
rm -f $PROTOC_ZIP

echo "install Golang 1.13.5"
curl -O https://storage.googleapis.com/golang/go1.13.5.linux-amd64.tar.gz
sudo tar -xf go1.13.5.linux-amd64.tar.gz -C /usr/local
mkdir -p ~/go/{bin,pkg,src}
echo "export GOPATH=$HOME/go" >> .bash_profile
echo "export PATH=$HOME/go/bin:/usr/local/go/bin:$PATH" >> .bash_profile
rm -f go1.13.5.linux-amd64.tar.gz

echo "install grpc gateway Go packages"
. .bash_profile
go get -u github.com/golang/protobuf/protoc-gen-go
go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway
go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger

check=$(grep "env.sh" .bash_profile)
if [ -z "${check}" ]; then
  echo "add env.sh to .bash_profile"
  echo ". ./env.sh" >> .bash_profile
fi