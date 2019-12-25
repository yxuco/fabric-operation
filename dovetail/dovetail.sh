#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# execute this script on bastion host to setup and build chaincode and client apps from Flogo flows
# usage: dovetail.sh <cmd> [options]
# e.g., dovetail.sh build-cds -s ./marble -j marble.json -c marble_cc
# or,   dovetail.sh build-app -j ./marble_client.json -c marble -o linux

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
FLOGO_VER=v0.9.4
VERSION="1.0"
BUILD_OS="linux"
BUILD_ARCH="amd64"

# install Flogo enterprise in $HOME
# installFE <FE-installer-zip-file>
function installFE {
  if [ -f "${1}" ]; then
    echo "install Flogo enterprise from file ${1}"
    # ignore large studio docker image from the zip
    unzip ${1} -x "**/docker/*" -d ${HOME}
    local fehome=$(find ${HOME}/flogo -name ?.? -print)
    rm ${1}
    echo "initialize go module for ${fehome}"
    ${DT_HOME}/fe-generator/init-gomod.sh ${fehome}
  else
    echo "cannot find FE installer file ${1}"
    return 1
  fi
}

# build CDS file on bastion host
# buildCDS <source-folder> <model-json> <cc-name> [<version>]
function buildCDS {
  local work_dir=${PWD}
  local chaincode=$(dirname "${SCRIPT_DIR}")/chaincode
  cd ${chaincode}
  local sFolder=${1}
  local ccName=${3}
  local version=${4:-"1.0"}

  # verify source folder
  if [ ! -d "${sFolder}" ]; then
    sFolder=${work_dir}/${sFolder}
    if [ ! -d "${sFolder}" ]; then
      echo "cannot find source folder ${sFolder}"
      return 1
    fi
  fi

  # cleanup old data
  if [ -d "${chaincode}/${ccName}" ]; then
    echo "cleanup old file in ${chaincode}/${ccName}"
    rm -Rf ${chaincode}/${ccName}
  fi

  flogo create --cv ${FLOGO_VER} -f ${sFolder}/${2} ${ccName}
  rm ${ccName}/src/main.go
  cp ${DT_HOME}/shim/chaincode_shim.go ${ccName}/src/main.go
  cp -Rf ${sFolder}/* ${ccName}/src
  cp ${DT_HOME}/flogo-patch/codegen.sh ${ccName}
  cd ${ccName}
  ./codegen.sh ${FE_HOME}
  if [ -f src/gomodedit.sh ]; then
    chmod +x src/gomodedit.sh
    cd src
    ./gomodedit.sh
  fi

  cd ${chaincode}/${ccName}
  flogo build -e
  cd src
  go get -u -d github.com/project-flogo/flow/activity/subflow@master
  go mod vendor
  cp -Rf ${DT_HOME}/flogo-patch/flow vendor/github.com/project-flogo
  cp -Rf ${DT_HOME}/flogo-patch/core vendor/github.com/project-flogo
  find vendor/github.com/TIBCOSoftware/dovetail-contrib/hyperledger-fabric/fabric/ -name '*_metadata.go' -exec rm {} \;
  go build -mod vendor -o ../${ccName}

  if [ ! -f "../${ccName}" ]; then
    echo "Failed to build ${ccName}"
    return 1
  fi

  # build cds
  cd $(dirname "${SCRIPT_DIR}")/network
  ./network.sh package-chaincode -n peer-0 -f ${ccName}/src -s ${ccName} -v ${version}
  
  local cds="${DATA_ROOT}/cli/${ccName}_${version}.cds"
  if [ -f "${cds}" ]; then
    sudo chmod +r ${cds}
    cp ${cds} ${SCRIPT_DIR}
    echo "created cds: ${SCRIPT_DIR}/${ccName}_${version}.cds"
  else
    echo "Failed to create CDS for chaincode in ${sFolder}"
    return 1
  fi
}

# build executable on bastion host
# buildApp <model-json> <app-name> [<goos> [<goarch>]]
function buildApp {
  local work_dir=${PWD}
  cd /tmp
  local model=${1}
  local appName=${2}
  local bOS=${3}
  if [ -z "${bOS}" ]; then
    bOS="linux"
  fi
  local bArch=${4:-"amd64"}

  # verify model file
  if [ ! -f "${model}" ]; then
    model=${work_dir}/${model}
    if [ ! -f "${model}" ]; then
      echo "cannot find model file ${model}"
      return 1
    fi
  fi

  # cleanup old data
  if [ -d "/tmp/${appName}" ]; then
    echo "cleanup old file in /tmp/${appName}"
    rm -Rf /tmp/${appName}
  fi

  flogo create --cv ${FLOGO_VER} -f ${model} ${appName}
  cp ${DT_HOME}/flogo-patch/codegen.sh ${appName}
  cd ${appName}
  ./codegen.sh ${FE_HOME}
  if [ -f src/gomodedit.sh ]; then
    chmod +x src/gomodedit.sh
    cd src
    ./gomodedit.sh
  fi

  cd /tmp/${appName}
  flogo build -e
  cd src
  go get -u -d github.com/project-flogo/flow/activity/subflow@master
  go mod vendor
  find vendor/github.com/TIBCOSoftware/dovetail-contrib/hyperledger-fabric/fabclient/ -name '*_metadata.go' -exec rm {} \;
  env GOOS=${bOS} GOARCH=${bArch} go build -mod vendor -o ${SCRIPT_DIR}/${appName}_${bOS}_${bArch}

  local app="${SCRIPT_DIR}/${appName}_${bOS}_${bArch}"
  if [ -f "${app}" ]; then
    echo "created app: ${app}"
  else
    echo "Failed to create app for model ${model}"
    return 1
  fi
}

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  dovetail.sh <cmd> [options]"
  echo "    <cmd> - one of the following commands"
  echo "      - 'install-fe' - install Flogo Enterprise from zip; arguments: -s <FE-installer-zip>"
  echo "      - 'build-cds' - build chaincode model to cds format; args; -s -j -c [-v]"
  echo "      - 'build-app' - upload and build fabric client app; args: -j -c -o [-a]"
  echo "    -p <property file> - the .env file in config folder that defines network properties, e.g., netop1 (default)"
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'"
  echo "    -s <source> - source folder name containing flogo model and other required files, e.g., ./marble"
  echo "    -j <json> - flogo model file in json format, e.g., marble.json"
  echo "    -c <cc-name> - chaincode or app name, e.g., marble_cc or marble_client"
  echo "    -v <version> - chaincode version, e.g., 1.0 (default)"
  echo "    -o <GOOS> - os for app executable, e.g., darwin or linux (default)"
  echo "    -a <GOARCH> - hardware arch for app executable, e.g., amd64 (default)"
  echo "  dovetail.sh -h (print this message)"
}

ORG_ENV="netop1"

CMD=${1}
shift
while getopts "h?p:t:s:j:c:v:o:a:" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  p)
    ORG_ENV=$OPTARG
    ;;
  t)
    ENV_TYPE=$OPTARG
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

source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORG_ENV} ${ENV_TYPE}
if [ "${ENV_TYPE}" == "docker" ]; then
  echo "docker not supported"
  exit 1
elif [ "${ENV_TYPE}" == "k8s" ]; then
  if [ -z "${DT_HOME}" ]; then
    echo "DT_HOME is not defined"
    exit 1
  fi
  if [ -z "${FE_HOME}" ]; then
    echo "FE_HOME is not defined"
    exit 1
  fi
else
  DT_HOME=${HOME}/dovetail-contrib/hyperledger-fabric
  if [ -d "${HOME}/flogo" ]; then
    FE_HOME=$(find ${HOME}/flogo -name ?.? -print)
  fi
fi

case "${CMD}" in
install-fe)
  installFE ${SOURCE}
  ;;
build-cds)
  echo "build cds from source ${SOURCE} for ${MODEL} ${APP_NAME} ${VERSION}"
  buildCDS "${SOURCE}" "${MODEL}" "${APP_NAME}" ${VERSION}
  ;;
build-app)
  echo "build client app for model ${MODEL} with ${APP_NAME} ${BUILD_OS} ${BUILD_ARCH}"
  buildApp "${MODEL}" "${APP_NAME}" "${BUILD_OS}" ${BUILD_ARCH}
  ;;
*)
  printHelp
  exit 1
esac
