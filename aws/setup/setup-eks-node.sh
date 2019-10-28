#!/bin/bash
# install amazon-efs-utils on a specified EKS nodes, or all EKS nodes if no node is specified
# usage: ./setup-eks-node.sh [ host [ host ] ]

cd "$( dirname "${BASH_SOURCE[0]}" )"
source ./env.sh

echo "mount EFS volume ${EFS_SERVER} to /${MOUNT_POINT}"
sudo mount -t nfs4 -o nfsvers=4.1 ${EFS_SERVER}:/ /${MOUNT_POINT}
sudo chown ec2-user:ec2-user /${MOUNT_POINT}

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
