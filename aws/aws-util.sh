#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create EKS cluster and setup EFS
# usage: aws-util.sh <cmd> [-n <name>] [-r <region>] [-p <profile>]"
# e.g., aws-util.sh create -n fab -r us-west-2 -p prod
# specify profile if aws user assume a role of a different account, the assumed role should be defined in ~/.aws/config

work_dir=${PWD}
SCRIPT_DIR=$( dirname "${BASH_SOURCE[0]}" )
cd ${SCRIPT_DIR}

# uploadFile <filename>
function uploadFile {
  echo "upload file ${1} to bastion host ${BASTION} ..."
  starttime=$(date +%s)

  # create bastion host if it does not exist already
  check=$(aws ec2 describe-instances --region ${AWS_REGION} --filters "Name=dns-name,Values=${BASTION}" --output text --query 'Reservations[*].Instances[*].State.Name')
  if [ "${check}" == "running" ]; then
    echo "bastion host ${BASTION} is already provisioned"
  else
    echo "Bastion host ${BASTION} must be created before continue"
    return 1
  fi

  local src=${1}
  if [ ! -f "${src}" ]; then
    src=${work_dir}/${1}
    if [ ! -f "${src}" ]; then
      echo "Cannot find source file ${1}"
      return 1
    fi
  fi
  scp -i ${SSH_PRIVKEY} -o "StrictHostKeyChecking no" ${src} ec2-user@${BASTION}:/home/ec2-user/
  echo "Uploaded ${1} to bastion host ${BASTION} in $(($(date +%s)-starttime)) seconds."
}

# downloadFile <remote-file> <local-folder>
function downloadFile {
  echo "download file ${1} from bastion host ${BASTION} to local ${2} ..."
  starttime=$(date +%s)

  # create bastion host if it does not exist already
  check=$(aws ec2 describe-instances --region ${AWS_REGION} --filters "Name=dns-name,Values=${BASTION}" --output text --query 'Reservations[*].Instances[*].State.Name')
  if [ "${check}" == "running" ]; then
    echo "bastion host ${BASTION} is already provisioned"
  else
    echo "Bastion host ${BASTION} must be created before continue"
    return 1
  fi

  local dest=${2}
  if [ -z "${2}" ]; then
    dest="."
  elif [ ! -d "${2}" ]; then
    mkdir -p ${2}
  fi
  scp -i ${SSH_PRIVKEY} -o "StrictHostKeyChecking no" ec2-user@${BASTION}:${1} ${dest}
  echo "Downloaded ${1} from bastion host ${BASTION} in $(($(date +%s)-starttime)) seconds."
}

# tar folder and upload to bastion host and then untar on bastion
# e.g., uplloadFolder <folder-path>
function uploadFolder {
  local dir=$(dirname "${1}")
  local file="${1##*/}"
  if [ ! -d "${dir}" ]; then
    dir=${work_dir}/${dir}
    if [ ! -d "${dir}" ]; then
      echo "Cannot find source folder ${1}"
      return 1
    fi
  fi

  cd ${dir}
  tar -czf ${file}.tar.gz ${file}
  echo "upload file ${file}.tar.gz"
  cd ${SCRIPT_DIR}
  uploadFile ${dir}/${file}.tar.gz
  echo "connect to bastion ec2-user@${BASTION}"
ssh -i ${SSH_PRIVKEY} -o "StrictHostKeyChecking no" ec2-user@${BASTION} << EOF
  echo "unzip file ${file}.tar.gz"
  tar -xzf ${file}.tar.gz
  rm ${file}.tar.gz
EOF
  echo "remove file ${file}.tar.gz"
  rm ${file}.tar.gz
}

function cleanup {
  echo "cleanup EKS cluster - ENV_NAME: ${ENV_NAME}, AWS_REGION: ${AWS_REGION}, AWS_PROFILE: ${AWS_PROFILE}"
  starttime=$(date +%s)

  ./cleanup-efs.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}
  ./cleanup-cluster.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}

  # cleanup EC2 volumes
  vols=$(aws ec2 describe-volumes --filter Name=status,Values=available --query Volumes[*].VolumeId --out text)
  array=( $vols )
  for v in "${array[@]}"; do
    echo "delete EC2 volume $v"
    aws ec2 delete-volume --volume-id $v
  done
  echo "Cleaned up ${EKS_STACK} in $(($(date +%s)-starttime)) seconds."
}

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  aws-util.sh <cmd> [-n <name>] [-r <region>] [-p <profile>]"
  echo "    <cmd> - one of the following commands"
  echo "      - 'create' - create EKS cluster and EFS storage"
  echo "      - 'cleanup' - shutdown EKS cluster and cleanup EFS storage"
  echo "      - 'upload-file' - upload a file to bastion host"
  echo "      - 'download-file' - download a file from bastion host to local folder"
  echo "      - 'upload-folder' - upload a folder of files to bastion host"
  echo "    -n <name> - prefix name of EKS cluster, e.g., fab (default)"
  echo "    -r <region> - AWS region to host the cluster, e.g. 'us-west-2' (default)"
  echo "    -p <profile> - AWS account profile name, e.g., 'prod'"
  echo "    -f <path> - Path of file or folder to upload/download to/from bastion host"
  echo "    -l <path> - Local folder path for downloading from bastion host"
  echo "  aws-util.sh -h (print this message)"
}

CMD=${1}
shift
while getopts "h?n:r:p:f:l:" opt; do
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
  f)
    FILE=$OPTARG
    ;;
  l)
    DEST=$OPTARG
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

echo "ENV_NAME: ${ENV_NAME}, AWS_REGION: ${AWS_REGION}, AWS_PROFILE: ${AWS_PROFILE}"
source env.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}

case "${CMD}" in
create)
  echo "create EKS cluster - ENV_NAME: ${ENV_NAME}, AWS_REGION: ${AWS_REGION}, AWS_PROFILE: ${AWS_PROFILE}"
  ./create-key-pair.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}
  ./create-cluster.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}
  ./deploy-efs.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}
  ./configure-bastion.sh ${ENV_NAME} ${AWS_REGION} ${AWS_PROFILE}
  ;;
cleanup)
  cleanup
  ;;
upload-file)
  echo "upload file ${FILE}"
  uploadFile ${FILE}
  ;;
download-file)
  echo "download file ${FILE} to ${DEST}"
  downloadFile ${FILE} ${DEST}
  ;;
upload-folder)
  echo "upload folder ${FILE}"
  uploadFolder ${FILE}
  ;;
*)
  printHelp
  exit 1
esac
