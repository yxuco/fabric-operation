#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# configure bastion host, and
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
sed -i -e "s|^AWS_MOUNT_POINT=.*|AWS_MOUNT_POINT=${MOUNT_POINT}|" ./fabric-operation/config/setup.sh
sed -i -e "s|^AWS_FSID=.*|AWS_FSID=${AWS_FSID}|" ./fabric-operation/config/setup.sh

check=$(grep "env.sh" .bash_profile)
if [ -z "${check}" ]; then
  echo "add env.sh to .bash_profile"
  echo ". ./env.sh" >> .bash_profile
fi