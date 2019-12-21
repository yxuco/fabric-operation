#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# Execute this script on bastion host to build specified chaincode or client app
# usage:
# ./dovetail-util.sh CDS <src-folder> <model> <name> [<version>]
# ./dovetail-util.sh CDS marble marble.json marble_cc 1.0
# or
# ./dovetail-util.sh APP <model> <name> <GOOS> [<GOARCH>]
# ./dovetail-util.sh APP marble_client.json marble darwin amd64
source ${HOME}/env.sh

TYPE=${1}

FLOGO_VER=v0.9.4
DT_HOME=${HOME}/dovetail-contrib/hyperledger-fabric

function buildCDS {
  cd $HOME
  flogo create --cv ${FLOGO_VER} -f ${SRC}/${MODEL} ${APP_NAME}
  rm ${APP_NAME}/src/main.go
  cp ${DT_HOME}/shim/chaincode_shim.go ${APP_NAME}/src/main.go
  cp -Rf ${SRC}/* ${APP_NAME}/src
  cp ${DT_HOME}/flogo-patch/codegen.sh ${APP_NAME}
  cd ${APP_NAME}
  ./codegen.sh ${FE_HOME}
  if [ -f src/gomodedit.sh ]; then
    chmod +x src/gomodedit.sh
    cd src
    ./gomodedit.sh
  fi

  cd $HOME/${APP_NAME}
  flogo build -e
  cd src
  go get -u -d github.com/project-flogo/flow/activity/subflow@master
  go mod vendor
  cp -Rf ${DT_HOME}/flogo-patch/flow vendor/github.com/project-flogo
  cp -Rf ${DT_HOME}/flogo-patch/core vendor/github.com/project-flogo
  find vendor/github.com/TIBCOSoftware/dovetail-contrib/hyperledger-fabric/fabric/ -name '*_metadata.go' -exec rm {} \;
  go build -mod vendor -o ../${APP_NAME}

  # build cds
  cp -Rf ${HOME}/${APP_NAME}/src $HOME/fabric-operation/chaincode/${APP_NAME}
  cd ${HOME}/fabric-operation/network
  ./network.sh package-chaincode -n peer-0 -f ${APP_NAME} -s ${APP_NAME} -v ${VERSION}
  
  local faborg=$(kubectl exec cli -- sh -c 'echo ${FABRIC_ORG}')
  cp /mnt/share/${faborg}/cli/${APP_NAME}_${VERSION}.cds ${HOME}
}

function cleanup {
  if [ "${TYPE}" == "CDS" ]; then
    rm -Rf ${SRC}
  else
    rm ${HOME}/${MODEL}
  fi
  rm -Rf $HOME/${APP_NAME}
}

function buildApp {
  cd $HOME
  flogo create --cv ${FLOGO_VER} -f ${MODEL} ${APP_NAME}
  cp ${DT_HOME}/flogo-patch/codegen.sh ${APP_NAME}
  cd ${APP_NAME}
  ./codegen.sh ${FE_HOME}
  if [ -f src/gomodedit.sh ]; then
    chmod +x src/gomodedit.sh
    cd src
    ./gomodedit.sh
  fi

  cd $HOME/${APP_NAME}
  flogo build -e
  cd src
  go get -u -d github.com/project-flogo/flow/activity/subflow@master
  go mod vendor
  find vendor/github.com/TIBCOSoftware/dovetail-contrib/hyperledger-fabric/fabclient/ -name '*_metadata.go' -exec rm {} \;
  env GOOS=${BUILD_OS} GOARCH=${BUILD_ARCH} go build -mod vendor -o ${HOME}/${APP_NAME}_${BUILD_OS}_${BUILD_ARCH}
}


if [ "${TYPE}" == "CDS" ]; then
  SRC=${HOME}/${2}
  MODEL=${3}
  APP_NAME=${4}
  VERSION=${5:-"1.0"}

  # cannot have same name for SRC and APP_NAME
  if [ "${APP_NAME}" == "${2}" ]; then
    mv ${SRC} ${SRC}_src
    SRC=${SRC}_src
  fi
  buildCDS
  if [ -f "${HOME}/${APP_NAME}_${VERSION}.cds" ]; then
    echo "created chaincodde ${APP_NAME}_${VERSION}.cds"
    cleanup
  fi
else
  MODEL=${2}
  APP_NAME=${3}
  BUILD_OS=${4}
  BUILD_ARCH=${5:-"amd64"}
  buildApp
  if [ -f "${HOME}/${APP_NAME}_${BUILD_OS}_${BUILD_ARCH}" ]; then
    echo "created executable ${APP_NAME}_${BUILD_OS}_${BUILD_ARCH}"
    cleanup
  fi
fi
