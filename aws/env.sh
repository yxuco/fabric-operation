#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# set AWS environment for a specified $ENV_NAME and $AWS_REGION
# usage: source env.sh env region profile
# specify profile if aws user assume a role of a different account, the assumed role should be defined in ~/.aws/config
# you may also set AWS_PROFILE=your_profile, and do not pass any variables to this script to use default config
# e.g., ENV_NAME="fab", AWS_REGION="us-west-2"

# number of EC2 instances to create for the cluster
export EKS_NODE_COUNT=3
# type of node instances to create
export EKS_NODE_TYPE=t2.medium
#export EKS_NODE_TYPE=m5.xlarge
export AWS_CLI_HOME=${HOME}/.aws

##### usually you do not need to modify parameters below this line

# return the full path of this script
function getScriptDir {
  local src="${BASH_SOURCE[0]}"
  while [ -h "$src" ]; do
    local dir ="$( cd -P "$( dirname "$src" )" && pwd )"
    src="$( readlink "$src" )"
    [[ $src != /* ]] && src="$dir/$src"
  done
  cd -P "$( dirname "$src" )" 
  pwd
}

export ENV_NAME=${1}
export AWS_REGION=${2}
if [[ ! -z "${3}" ]]; then
  export AWS_PROFILE=${3}
fi

export AWS_ZONES=${AWS_REGION}a,${AWS_REGION}b,${AWS_REGION}c
export EKS_STACK=${ENV_NAME}-eks-stack
export EFS_STACK=${ENV_NAME}-efs-client
export S3_BUCKET=${ENV_NAME}-s3-share
export EFS_VOLUME=vol-${ENV_NAME}
export BASTION=ec2-18-236-71-9.us-west-2.compute.amazonaws.com

export SCRIPT_HOME=$(getScriptDir)
export KUBECONFIG=${SCRIPT_HOME}/config/config-${ENV_NAME}.yaml
export EFS_CONFIG=${SCRIPT_HOME}/config/${EFS_STACK}.yaml
export KEYNAME=${ENV_NAME}-keypair
export SSH_PUBKEY=${SCRIPT_HOME}/config/${KEYNAME}.pub
export SSH_PRIVKEY=${SCRIPT_HOME}/config/${KEYNAME}.pem

if [ ! -f ${SSH_PRIVKEY} ]; then
  mkdir -p ${SCRIPT_HOME}/config
fi
