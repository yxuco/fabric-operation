#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

region=$(aws configure get region)

bastionSgid=$(aws ec2 describe-security-groups --filters Name=group-name,Values=${EFS_STACK}-InstanceSecurityGroup* --query 'SecurityGroups[*].GroupId' --output text)
nodeSgid=$(aws ec2 describe-security-groups --filters Name=group-name,Values=eksctl-${EKS_STACK}-nodegroup-ng* --query 'SecurityGroups[*].GroupId' --output text)
echo "remove security rule for bastion host ${bastionSgid} access to EKS nodes ${nodeSgid}"
aws ec2 revoke-security-group-ingress --group-id ${nodeSgid} --protocol tcp --port 22 --source-group ${bastionSgid}

echo "delete stack ${EFS_STACK} in region ${region}"
aws cloudformation delete-stack --stack-name ${EFS_STACK}
