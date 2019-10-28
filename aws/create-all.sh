#!/bin/bash
# create EKS cluster and setup EFS
# usage: create-all.sh env region profile
# e.g., create-all.sh dev us-west-2
# specify profile if aws user assume a role of a different account, the assumed role should be defined in ~/.aws/config

cd "$( dirname "${BASH_SOURCE[0]}" )"

source env.sh "$@"
sed -i -e "s/^export ENV_NAME=.*/export ENV_NAME=${ENV_NAME}/" ./setup/env.sh
sed -i -e "s/^export EKS_STACK=.*/export EKS_STACK=${EKS_STACK}/g" ./setup/env.sh
sed -i -e "s/^export SSH_PRIVKEY=.*/export SSH_PRIVKEY=${KEYNAME}.pem/g" ./setup/env.sh
if [[ ! -z "${AWS_PROFILE}" ]]; then
  sed -i -e "s/^export AWS_PROFILE=.*/export AWS_PROFILE=${AWS_PROFILE}/" ./setup/env.sh
else
  sed -i -e "s/^export AWS_PROFILE=.*/export AWS_PROFILE=/" ./setup/env.sh
fi

# create key pair for managing EFS
./create-key-pair.sh

# create s3 buckets for sharing files
./create-s3-bucket.sh

# create EKS cluster and setup EKS nodes
./create-cluster.sh

# create EFS volume and bastion host for EFS client
./deploy-efs.sh

# set rules for security groups, so it won't open to the world
./bastion-sg-rule.sh

# initilaize bastion host
./setup-bastion.sh

# verify installation of jq
jq --version
if [ $? -ne 0 ]; then
  echo ""
  echo "jq is not in PATH. You will need it to run cleanup scripts."
  echo "jq installation: https://github.com/stedolan/jq/wiki/Installation"
fi
