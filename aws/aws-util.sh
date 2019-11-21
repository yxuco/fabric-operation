#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create EKS cluster and setup EFS
# usage: aws-util.sh <cmd> [-n <name>] [-r <region>] [-p <profile>]"
# e.g., aws-util.sh create -n fab -r us-west-2 -p prod
# specify profile if aws user assume a role of a different account, the assumed role should be defined in ~/.aws/config

cd "$( dirname "${BASH_SOURCE[0]}" )"

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  aws-util.sh <cmd> [-n <name>] [-r <region>] [-p <profile>]"
  echo "    <cmd> - one of 'create', or 'cleanup'"
  echo "      - 'create' - create EKS cluster and EFS storage"
  echo "      - 'cleanup' - shutdown EKS cluster and cleanup EFS storage"
  echo "    -n <name> - prefix name of EKS cluster, e.g., fab (default)"
  echo "    -r <region> - AWS region to host the cluster, e.g. 'us-west-2' (default)"
  echo "    -p <profile> - AWS account profile name, e.g., 'prod'"
  echo "  aws-util.sh -h (print this message)"
}

CMD=${1}
shift
while getopts "h?n:r:p:" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  n)
    ENV_NAME=$OPTARG
    ;;
  r)
    AWS_REGION=$OPTARG
    ;;
  p)
    AWS_PROFILE=$OPTARG
    ;;
  esac
done

if [ -z "${ENV_NAME}" ]; then
  ENV_NAME="fab"
fi

if [ -z "${AWS_REGION}" ]; then
  AWS_REGION=$(aws configure get region)
  if [ -z "${AWS_REGION}" ]; then
    AWS_REGION="us-west-2"
  fi
fi
aws configure set region ${AWS_REGION}

case "${CMD}" in
create)
  echo "create EKS cluster - ENV_NAME: ${ENV_NAME}, AWS_REGION: ${AWS_REGION}, AWS_PROFILE: ${AWS_PROFILE}"
  ./create-key-pair.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}
  ./create-cluster.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}
  ./deploy-efs.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}
  ./configure-bastion.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}
  ;;
cleanup)
  echo "cleanup EKS cluster - ENV_NAME: ${ENV_NAME}, AWS_REGION: ${AWS_REGION}, AWS_PROFILE: ${AWS_PROFILE}"
  source env.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}

  ./cleanup-efs.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}
  ./cleanup-cluster.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}

  # cleanup EC2 volumes
  vols=$(aws ec2 describe-volumes --filter Name=status,Values=available --query Volumes[*].VolumeId --out text)
  array=( $vols )
  for v in "${array[@]}"; do
    echo "delete EC2 volume $v"
    aws ec2 delete-volume --volume-id $v
  done
  ;;
*)
  printHelp
  exit 1
esac
