#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh

starttime=$(date +%s)
aws configure set default.region ${AWS_REGION}
bastionHost=$(aws ec2 describe-instances --region ${AWS_REGION} --query 'Reservations[*].Instances[*].PublicDnsName' --output text --filters "Name=tag:Name,Values=${EFS_STACK}-instance" "Name=instance-state-name,Values=running")
sed -i -e "s|BASTION=.*|BASTION=${bastionHost}|" ./env.sh

echo "setup bastion host ${bastionHost} ..."
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ${AWS_CLI_HOME}/config ec2-user@${bastionHost}:/home/ec2-user/
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ${AWS_CLI_HOME}/credentials ec2-user@${bastionHost}:/home/ec2-user/
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ${KUBECONFIG} ec2-user@${bastionHost}:/home/ec2-user/
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ${SSH_PRIVKEY} ec2-user@${bastionHost}:/home/ec2-user/.ssh/
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ./setup/env.sh ec2-user@${bastionHost}:/home/ec2-user/
scp -i ${SSH_PRIVKEY} -q -o "StrictHostKeyChecking no" ./setup/setup-eks-node.sh ec2-user@${bastionHost}:/home/ec2-user/

echo "ssh on ${bastionHost} to setup env ..."
ssh -i ${SSH_PRIVKEY} -o "StrictHostKeyChecking no" ec2-user@${bastionHost} << EOF
  echo "setup AWS and Kubernetes environment"
  mkdir -p .aws
  mv config .aws
  mv credentials .aws
  mkdir -p .kube
  mv config-*.yaml .kube/config

  echo "setup EKS nodes"
  ./setup-eks-node.sh
EOF

# echo "copy admin scripts to EFS ..."
# scp -i ${SSH_PRIVKEY} -q -r ../admin ec2-user@${bastionHost}:/opt/share/scripts

echo "setup completed in $(($(date +%s)-starttime)) seconds."
echo "login on bastion host using the following command:"
echo "  ssh -i ${SSH_PRIVKEY} ec2-user@${bastionHost}"
