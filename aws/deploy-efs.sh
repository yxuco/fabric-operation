#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

vpcId=$(aws eks describe-cluster --name ${EKS_STACK} --query 'cluster.resourcesVpcConfig.vpcId' --output text)
subnetIds=$(aws eks describe-cluster --name ${EKS_STACK} --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
array=( ${subnetIds} )

echo "create EFS volume for vpcId: ${vpcId} and subnets: ${array[0]} ${array[1]} ${array[2]}"
echo "it may take 6 minutes ..."

mountpoint=opt/share

starttime=$(date +%s)
sed "s/{{ec2-instance}}/${EFS_STACK}-instance/g" ec2-for-efs-3AZ.yaml > ${EFS_CONFIG}
aws cloudformation deploy --stack-name ${EFS_STACK} --template-file ${EFS_CONFIG} \
--capabilities CAPABILITY_NAMED_IAM \
--parameter-overrides VPCId=${vpcId} SubnetA=${array[0]} SubnetB=${array[1]} SubnetC=${array[2]} \
KeyName=${KEYNAME} VolumeName=${EFS_VOLUME} MountPoint=${mountpoint} \
--region ${AWS_REGION}

echo "EFS volume ${EFS_VOLUME} created in $(($(date +%s)-starttime)) seconds."

filesysid=$(aws efs describe-file-systems --query 'FileSystems[?Name==`'${EFS_VOLUME}'`].FileSystemId' --output text)
echo "configure EFS_SERVER for filesystem id: ${filesysid}"
sed -i -e "s/^export EFS_SERVER=.*/export EFS_SERVER=${filesysid}.efs.${AWS_REGION}.amazonaws.com/" ./setup/env.sh
sed -i -e "s/^export EFS_STACK=.*/export EFS_STACK=${EFS_STACK}/" ./setup/env.sh
sed -i -e "s|^export MOUNT_POINT=.*|export MOUNT_POINT=${mountpoint}|" ./setup/env.sh

# update fabric config env
sed -i -e "s|^export AWS_MOUNT_POINT=.*|export AWS_MOUNT_POINT=${mountpoint}|" ./setup/env.sh
sed -i -e "s|^export AWS_FSID=.*|export AWS_FSID=${filesysid}|" ./setup/env.sh
