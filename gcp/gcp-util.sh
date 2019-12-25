#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create GCP cluster and Cloud Filestore
# usage: gcp-util.sh <cmd> [-n <name>] [-r <zone>]
# e.g., gcp-util.sh create -n fab -r us-west1-c

work_dir=${PWD}
SCRIPT_DIR=$( dirname "${BASH_SOURCE[0]}" )
cd ${SCRIPT_DIR}

# uploadFile <filename>
function uploadFile {
  echo "upload file ${1} to bastion host ${BASTION_HOST} ..."
  starttime=$(date +%s)

  # create bastion host if it does not exist already
  check=$(gcloud compute instances describe ${BASTION_HOST} --format="csv[no-heading](status)")
  if [ "${check}" == "RUNNING" ]; then
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
  gcloud compute scp --ssh-key-file ./config/${SSH_KEY} ${src} ${BASTION_USER}@${BASTION_HOST}:
  echo "Uploaded ${1} to bastion host ${BASTION_HOST} in $(($(date +%s)-starttime)) seconds."
}

# downloadFile <remote-file> <local-folder>
function downloadFile {
  echo "download file ${1} from bastion host ${BASTION_HOST} to local ${2} ..."
  starttime=$(date +%s)

  # create bastion host if it does not exist already
  check=$(gcloud compute instances describe ${BASTION_HOST} --format="csv[no-heading](status)")
  if [ "${check}" == "RUNNING" ]; then
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
  gcloud compute scp --ssh-key-file ./config/${SSH_KEY} ${BASTION_USER}@${BASTION_HOST}:${1} ${dest}
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
  echo "connect to bastion ${BASTION_USER}@${BASTION_HOST}"
gcloud compute ssh --ssh-key-file ./config/${SSH_KEY} ${BASTION_USER}@${BASTION_HOST} << EOF
  echo "unzip file ${file}.tar.gz"
  tar -xzf ${file}.tar.gz
  rm ${file}.tar.gz
EOF
  echo "remove file ${file}.tar.gz"
  rm ${file}.tar.gz
}

function cleanup {
  starttime=$(date +%s)
  echo "cleanup may take 5 mminutes ..."

  echo "delete bastion host ${BASTION_HOST}"
  gcloud compute instances delete ${BASTION_HOST} --quiet
  echo "delete Cloud Filestore ${FILESTORE}"
  gcloud filestore instances delete ${FILESTORE} --quiet
  echo "delete GKE cluster ${GKE_CLUSTER}"
  gcloud container clusters delete ${GKE_CLUSTER} --quiet

  echo "Cleaned up ${GCP_PROJECT} in $(($(date +%s)-starttime)) seconds."
}

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  gcp-util.sh <cmd> [options]"
  echo "    <cmd> - one of the following commands"
  echo "      - 'create' - create GKE cluster and Cloud Filestore"
  echo "      - 'cleanup' - shutdown GKE cluster and cleanup Cloud Filestore"
  echo "      - 'upload-file' - upload a file to bastion host"
  echo "      - 'download-file' - download a file from bastion host to local folder"
  echo "      - 'upload-folder' - upload a folder of files to bastion host"
  echo "    -n <name> - prefix name of GKE cluster, e.g., fab (default)"
  echo "    -r <zone> - GCP region and zone to host the cluster, e.g. 'us-west1-c' (default)"
  echo "    -f <path> - Path of file or folder to upload/download to/from bastion host"
  echo "    -l <path> - Local folder path for downloading from bastion host"
  echo "  gcp-util.sh -h (print this message)"
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
    GCP_ZONE=$OPTARG
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

if [ -z "${GCP_ZONE}" ]; then
    GCP_ZONE="us-west1-c"
fi

echo "ENV_NAME: ${ENV_NAME}, GCP_ZONE: ${GCP_ZONE}"
source env.sh ${ENV_NAME} ${GCP_ZONE}

case "${CMD}" in
create)
  echo "create GKE cluster - ENV_NAME: ${ENV_NAME}, GCP_ZONE: ${GCP_ZONE}"
  echo "it may take 7-8 minutes ..."
  ./create-cluster.sh ${ENV_NAME} ${GCP_ZONE}
  ./create-storage.sh ${ENV_NAME} ${GCP_ZONE}
  ./create-bastion.sh ${ENV_NAME} ${GCP_ZONE}
  ;;
cleanup)
  echo "cleanup GKE cluster"
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
