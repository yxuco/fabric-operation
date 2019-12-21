#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# setup and build chaincode and client apps from Flogo flows
# usage: dovetail.sh <cmd> -p <platform> [options]
# e.g., dovetail.sh build-cds -p az -n fab -s samples/marble -j marble.json -c marble_cc
# or,   dovetail.sh build-app -p az -n fab -j samples/marble/marble_client.json -c marble -o darwin

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"

# set environment vars for target platform
function setEnv {
  cd ${SCRIPT_DIR}
  if [ -f "../${PLATFORM}/env.sh" ]; then
    echo "set env for ${PLATFORM} and ${ENV_NAME}"
    source ../${PLATFORM}/env.sh ${ENV_NAME}
  else
    echo "env.sh not found for platform ${PLATFORM}"
  fi
}

# azUploadFile <filename>
function azUploadFile {
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

  if [ -f "${1}" ]; then
    scp ${1} ${BASTION_USER}@${BASTION_IP}:
  else
    echo "Cannot find source file ${1}"
    return 1
  fi
  echo "Uploaded ${1} to bastion host ${BASTION_HOST} in $(($(date +%s)-starttime)) seconds."
}

# azSetupFE <FE-installer-zip-file>
function azSetupFE {
  cd ${SCRIPT_DIR}
  azUploadFile ${1}
  if [ $? -eq 0 ]; then
    # setup $FE_HOME
ssh -o "StrictHostKeyChecking no" ${BASTION_USER}@${BASTION_IP} << EOF
  unzip ${1}
  echo "export FE_HOME=\$HOME/$(find flogo -name ?.? -print)" >> ./env.sh
  rm ${1}
  . ./env.sh
  echo "initialize go module for \$FE_HOME"
  ./dovetail-contrib/hyperledger-fabric/fe-generator/init-gomod.sh \$FE_HOME
EOF
  fi
}

# setupFE <FE-zip-file>
# e.g., setupFE TIB_flogo_2.8.0_macosx_x86_64.zip
function setupFE {
  if [ "${PLATFORM}" == "az" ]; then
    azSetupFE ${1}
  fi
}

# tar folder and upload to bastion host and then untar on bastion
# e.g., uplloadFolder
function uploadFolder {
  local fp="${SCRIPT_DIR}/${SOURCE}"
  local dir=$(dirname "${fp}")
  local file="${fp##*/}"
  cd ${dir}
  tar -czf ${file}.tar.gz ${file}
  if [ "${PLATFORM}" == "az" ]; then
    echo "upload file ${file}.tar.gz"
    azUploadFile ${file}.tar.gz
    echo "connect to bastion ${BASTION_USER}@${BASTION_IP}"
ssh -o "StrictHostKeyChecking no" ${BASTION_USER}@${BASTION_IP} << EOF
  echo "unzip file ${file}.tar.gz"
  tar -xzf ${file}.tar.gz
  rm ${file}.tar.gz
EOF
  fi
  echo "remove file ${file}.tar.gz"
  rm ${file}.tar.gz
}

function uploadFile {
  if [ "${PLATFORM}" == "az" ]; then
    azUploadFile ${1}
  fi
}

# build CDS file on bastion host, and scp to source folder
function buildCDS {
  local src="${SOURCE##*/}"
  if [ "${PLATFORM}" == "az" ]; then
    echo "build CDS for ${src}"
ssh -o "StrictHostKeyChecking no" ${BASTION_USER}@${BASTION_IP} << EOF
  echo "build CDS with args; ${src} ${MODEL} ${APP_NAME} ${VERSION}"
  ./fabric-operation/dovetail/dovetail-util.sh CDS "${src}" "${MODEL}" "${APP_NAME}" ${VERSION}
EOF
    scp ${BASTION_USER}@${BASTION_IP}:${APP_NAME}_${VERSION}.cds $(dirname "${SCRIPT_DIR}/${SOURCE}")
  fi
}

# build executable on bastion host, and scp to source folder
function buildApp {
  local src="${MODEL##*/}"
  if [ "${PLATFORM}" == "az" ]; then
    echo "build App for ${src}"
ssh -o "StrictHostKeyChecking no" ${BASTION_USER}@${BASTION_IP} << EOF
  echo "build App with args: ${src} ${APP_NAME} ${BUILD_OS} ${BUILD_ARCH}"
  ./fabric-operation/dovetail/dovetail-util.sh APP "${src}" "${APP_NAME}" "${BUILD_OS}" ${BUILD_ARCH}
EOF
    scp ${BASTION_USER}@${BASTION_IP}:${APP_NAME}_${BUILD_OS}_${BUILD_ARCH} $(dirname "${SCRIPT_DIR}/${MODEL}")
  fi
}

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  dovetail.sh <cmd> -p <platform> [options]"
  echo "    <cmd> - one of the following commands"
  echo "      - 'upload-fe' - upload Flogo Enterprise installer to bastion host; arguments: -s <FE-installer-zip>"
  echo "      - 'build-cds' - upload and build chaincode model to cds format; args; -s -j -c [-v]"
  echo "      - 'build-app' - upload and build fabric client app; args: -j -c -o [-a]"
  echo "    -p <platform> - cloud environment: az, aws, gcp, or k8s (default)"
  echo "    -n <name> - prefix name of kubernetes environment, e.g., fab (default)"
  echo "    -s <source> - source folder name containing flogo model and other required files, e.g., samples/marble"
  echo "    -j <json> - flogo model file in json format, e.g., marble.json"
  echo "    -c <cc-name> - chaincode or app name, e.g., marble_cc or marble_client"
  echo "    -v <version> - chaincode version, e.g., 1.0 (default)"
  echo "    -o <GOOS> - os for app executable, e.g., darwin or linux"
  echo "    -a <GOARCH> - hardware arch for app executable, e.g., amd64 (default)"
  echo "  dovetail.sh -h (print this message)"
}

VERSION="1.0"
PLATFORM="k8s"
BUILD_ARCH="amd64"

CMD=${1}
shift
while getopts "h?p:n:s:j:c:v:o:a:" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  p)
    PLATFORM=$OPTARG
    ;;
  n)
    ENV_NAME=$OPTARG
    ;;
  s)
    SOURCE=$OPTARG
    ;;
  j)
    MODEL=$OPTARG
    ;;
  c)
    APP_NAME=$OPTARG
    ;;
  v)
    VERSION=$OPTARG
    ;;
  o)
    BUILD_OS=$OPTARG
    ;;
  a)
    BUILD_ARCH=$OPTARG
    ;;
  esac
done

if [ -z "${ENV_NAME}" ]; then
  ENV_NAME="fab"
fi
setEnv

case "${CMD}" in
upload-fe)
  setupFE ${SOURCE}
  ;;
build-cds)
  echo "build cds from source ${SOURCE} for ${MODEL} ${APP_NAME} ${VERSION}"
  uploadFolder
  buildCDS
  ;;
build-app)
  echo "build client app from source ${MODEL} for ${APP_NAME} ${BUILD_OS} ${BUILD_ARCH}"
  uploadFile ${MODEL}
  buildApp
  ;;
*)
  printHelp
  exit 1
esac
