#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

vpcId=$(aws eks describe-cluster --name ${EKS_STACK} --query 'cluster.resourcesVpcConfig.vpcId' --output text)
subnetIds=$(aws eks describe-cluster --name ${EKS_STACK} --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
array=( ${subnetIds} )

echo "create EFS volume for vpcId: ${vpcId} and subnets: ${array[0]} ${array[1]} ${array[2]}"
echo "it may take 6 minutes ..."

mountpoint=mnt/share

starttime=$(date +%s)
sed "s/{{ec2-instance}}/${EFS_STACK}-instance/g" ec2-for-efs-3AZ.yaml > ${EFS_CONFIG}
aws cloudformation deploy --stack-name ${EFS_STACK} --template-file ${EFS_CONFIG} \
--capabilities CAPABILITY_NAMED_IAM \
--parameter-overrides VPCId=${vpcId} SubnetA=${array[0]} SubnetB=${array[1]} SubnetC=${array[2]} \
KeyName=${KEYNAME} VolumeName=${EFS_VOLUME} MountPoint=${mountpoint} \
--region ${AWS_REGION}

# set env for bastion host configuration
filesysid=$(aws efs describe-file-systems --query 'FileSystems[?Name==`'${EFS_VOLUME}'`].FileSystemId' --output text)
echo "created EFS_SERVER for filesystem id: ${filesysid}"
echo "export EKS_STACK=${EKS_STACK}" > ./config/env.sh
echo "export EFS_SERVER=${filesysid}.efs.${AWS_REGION}.amazonaws.com" >> ./config/env.sh
echo "export AWS_FSID=${filesysid}" >> ./config/env.sh
echo "export MOUNT_POINT=${mountpoint}" >> ./config/env.sh
echo "export SSH_PRIVKEY=${KEYNAME}.pem" >> ./config/env.sh
if [[ ! -z "${AWS_PROFILE}" ]]; then
  echo "export AWS_PROFILE=${AWS_PROFILE}" >> ./config/env.sh
fi

# set limited SSH rule for bastion host
mycidr=$(curl ifconfig.me)/32
echo "export MYCIDR=${mycidr}" >> ./config/env.sh
bastionSgid=$(aws ec2 describe-security-groups --filters Name=group-name,Values=${EFS_STACK}-InstanceSecurityGroup* --query 'SecurityGroups[*].GroupId' --output text)
echo "set ssh rule for ${mycidr} to access bastion host ${bastionSgid}"
aws ec2 revoke-security-group-ingress --group-id ${bastionSgid} --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id ${bastionSgid} --protocol tcp --port 22 --cidr ${mycidr}

# set limited NFS rules for EFS mount
mountSgid=$(aws ec2 describe-security-groups --filters Name=group-name,Values=${EFS_STACK}-MountTargetSecurityGroup* --query 'SecurityGroups[*].GroupId' --output text)
nodeSgid=$(aws ec2 describe-security-groups --filters Name=group-name,Values=eksctl-${EKS_STACK}-nodegroup-ng* --query 'SecurityGroups[*].GroupId' --output text)
echo "set NFS rule for bastion sg ${bastionSgid} and node sg ${nodeSgid} to access EFS mount ${mountSgid}"
aws ec2 authorize-security-group-ingress --group-id ${mountSgid} --protocol tcp --port 2049 --source-group ${bastionSgid}
aws ec2 authorize-security-group-ingress --group-id ${mountSgid} --protocol tcp --port 2049 --source-group ${nodeSgid}

# allow bastion host ssh into nodes
echo "set ssh rule for bastion sg ${bastionSgid} to access nodes ${nodeSgid}"
aws ec2 authorize-security-group-ingress --group-id ${nodeSgid} --protocol tcp --port 22 --source-group ${bastionSgid}

echo "EFS volume ${EFS_VOLUME} created in $(($(date +%s)-starttime)) seconds."
