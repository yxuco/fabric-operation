#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

starttime=$(date +%s)
aws configure set default.region ${AWS_REGION}
bastionHost=$(aws ec2 describe-instances --region ${AWS_REGION} --query 'Reservations[*].Instances[*].PublicDnsName' --output text --filters "Name=tag:Name,Values=${EFS_STACK}-instance" "Name=instance-state-name,Values=running")
sed -i -e "s|BASTION=.*|BASTION=${bastionHost}|" ./env.sh

echo "setup bastion host ${bastionHost} ..."
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ${AWS_CLI_HOME}/config ec2-user@${bastionHost}:/home/ec2-user/
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ${AWS_CLI_HOME}/credentials ec2-user@${bastionHost}:/home/ec2-user/
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ./config/config-${ENV_NAME}.yaml ec2-user@${bastionHost}:/home/ec2-user/config.yaml
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ${SSH_PRIVKEY} ec2-user@${bastionHost}:/home/ec2-user/.ssh/
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ./config/env.sh ec2-user@${bastionHost}:/home/ec2-user/
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ./setup-eks-node.sh ec2-user@${bastionHost}:/home/ec2-user/setup.sh

echo "ssh on ${bastionHost} to setup env ..."
ssh -i ${SSH_PRIVKEY} -o "StrictHostKeyChecking no" ec2-user@${bastionHost} << EOF
  ./setup.sh
EOF

echo "setup completed in $(($(date +%s)-starttime)) seconds."
echo "login on bastion host using the following command:"
echo "  ssh -i ${SSH_PRIVKEY} ec2-user@${bastionHost}"
