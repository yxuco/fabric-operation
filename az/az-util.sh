#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create AKS cluster and Azure File storage
# usage: az-util.sh <cmd> [-n <name>] [-r <region>]
# e.g., az-util.sh create -n fab -r westus2

work_dir=${PWD}
SCRIPT_DIR=$( dirname "${BASH_SOURCE[0]}" )
cd ${SCRIPT_DIR}

# uploadFile <filename>
function uploadFile {
  echo "upload file ${1} to bastion host ${BASTION_HOST} ..."
  starttime=$(date +%s)

  # create bastion host if it does not exist already
  check=$(az vm show -n ${BASTION_HOST} -g ${RESOURCE_GROUP} --query "provisioningState" -o tsv)
  if [ "${check}" == "Succeeded" ]; then
    echo "bastion host ${BASTION_HOST} is already provisioned"
  else
    echo "Bastion host ${BASTION_HOST} must be created before continue"
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
  scp ${src} ${BASTION_USER}@${BASTION_IP}:
  echo "Uploaded ${1} to bastion host ${BASTION_HOST} in $(($(date +%s)-starttime)) seconds."
}

# downloadFile <remote-file> <local-folder>
function downloadFile {
  echo "download file ${1} from bastion host ${BASTION_HOST} to local ${2} ..."
  starttime=$(date +%s)

  # create bastion host if it does not exist already
  check=$(az vm show -n ${BASTION_HOST} -g ${RESOURCE_GROUP} --query "provisioningState" -o tsv)
  if [ "${check}" == "Succeeded" ]; then
    echo "bastion host ${BASTION_HOST} is already provisioned"
  else
    echo "Bastion host ${BASTION_HOST} must be created before continue"
    return 1
  fi

  local dest=${2}
  if [ -z "${2}" ]; then
    dest="."
  elif [ ! -d "${2}" ]; then
    mkdir -p ${2}
  fi
  scp ${BASTION_USER}@${BASTION_IP}:${1} ${dest}
  echo "Downloaded ${1} from bastion host ${BASTION_HOST} in $(($(date +%s)-starttime)) seconds."
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
  echo "connect to bastion ${BASTION_USER}@${BASTION_IP}"
ssh -o "StrictHostKeyChecking no" ${BASTION_USER}@${BASTION_IP} << EOF
  echo "unzip file ${file}.tar.gz"
  tar -xzf ${file}.tar.gz
  rm ${file}.tar.gz
EOF
  echo "remove file ${file}.tar.gz"
  rm ${file}.tar.gz
}

function cleanup {
  starttime=$(date +%s)
  echo "cleanup may take 10-11 mminutes ..."

  echo "delete bastion host ${BASTION_HOST}"
  az vm delete -n ${BASTION_HOST} -g ${RESOURCE_GROUP} -y
  echo "delete Azure File storage ${STORAGE_ACCT}"
  az storage account delete -n ${STORAGE_ACCT} -y
  echo "delete AKS cluster ${AKS_CLUSTER}"
  az aks delete -g ${RESOURCE_GROUP} -n ${AKS_CLUSTER} -y
  echo "delete resource group ${RESOURCE_GROUP}"
  az group delete -n ${RESOURCE_GROUP} -y

  echo "Cleaned up ${RESOURCE_GROUP} in $(($(date +%s)-starttime)) seconds."
}

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  az-util.sh <cmd> [options]"
  echo "    <cmd> - one of the following commands"
  echo "      - 'create' - create AKS cluster and Azure Files storage"
  echo "      - 'cleanup' - shutdown AKS cluster and cleanup Azure Files storage"
  echo "      - 'upload-file' - upload a file to bastion host"
  echo "      - 'download-file' - download a file from bastion host to local folder"
  echo "      - 'upload-folder' - upload a folder of files to bastion host"
  echo "    -n <name> - prefix name of AKS cluster, e.g., fab (default)"
  echo "    -r <region> - Azure location to host the cluster, e.g. 'westus2' (default)"
  echo "    -f <path> - Path of file or folder to upload/download to/from bastion host"
  echo "    -l <path> - Local folder path for downloading from bastion host"
  echo "  az-util.sh -h (print this message)"
}

CMD=${1}
shift
while getopts "h?n:r:f:l:" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  n)
    ENV_NAME=$OPTARG
    ;;
  r)
    AZ_REGION=$OPTARG
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

if [ -z "${AZ_REGION}" ]; then
    AZ_REGION="westus2"
fi

echo "ENV_NAME: ${ENV_NAME}, AZ_REGION: ${AZ_REGION}"
source env.sh ${ENV_NAME} ${AZ_REGION}

case "${CMD}" in
create)
  echo "create AKS cluster"
  ./create-cluster.sh ${ENV_NAME} ${AZ_REGION}
  ./create-storage.sh ${ENV_NAME} ${AZ_REGION}
  ./create-bastion.sh ${ENV_NAME} ${AZ_REGION}
  ;;
cleanup)
  echo "cleanup AKS cluster"
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
