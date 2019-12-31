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
  if [ -z "${DT_HOME}" ]; then
    echo "DT_HOME is not defined"
    return 1
  fi
  if [ -z "${FE_HOME}" ]; then
    echo "FE_HOME is not defined, so model cannot use Flogo Enterprise components"
  fi

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
    ${sucp} ${cds} ${SCRIPT_DIR}
    echo "created cds: ${SCRIPT_DIR}/${ccName}_${version}.cds"
  else
    echo "Failed to create CDS for chaincode in ${sFolder}"
    return 1
  fi
}

# build executable on bastion host
# buildApp <model-json> <app-name> [<goos> [<goarch>]]
function buildApp {
  if [ -z "${DT_HOME}" ]; then
    echo "DT_HOME is not defined"
    return 1
  fi
  if [ -z "${FE_HOME}" ]; then
    echo "FE_HOME is not defined, model should not use Flogo Enterprise components"
  fi

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

function configureApp {
  local network="${DATA_ROOT}/gateway/config/config_${CHANNEL_ID}.yaml"
  if [ ! -f "${network}" ]; then
    echo "create network config"
    ${sumd} -p ${DATA_ROOT}/gateway/config
    printNetworkYaml ${CHANNEL_ID} | ${stee} ${network} > /dev/null
  fi

  local modelFile=${MODEL##*/}
  local modelName=${modelFile%.*}
  modelName=${modelName//_/-}
  echo "config client app for model ${MODEL} with ${network}"
  setNetworkConfig "${MODEL}" "${network}" > ${MODEL}.tmp
  setEntityMatcher "${MODEL}.tmp" | ${stee} ${DATA_ROOT}/gateway/${modelFile} > /dev/null
  rm ${MODEL}.tmp

  echo "create app k8s yaml files"
  ${sumd} -p ${DATA_ROOT}/gateway/k8s
  printStorageYaml ${modelName} | ${stee} ${DATA_ROOT}/gateway/k8s/${modelName}-pv.yaml > /dev/null
  printAppYaml ${modelName} | ${stee} ${DATA_ROOT}/gateway/k8s/${modelName}.yaml > /dev/null
}

function startApp {
  local modelFile=${MODEL##*/}
  local modelName=${modelFile%.*}
  modelName=${modelName//_/-}
  if [ ! -f "${DATA_ROOT}/gateway/${modelName}_linux_amd64" ]; then
    # need to build executable for model
    if [ ! -f "${DATA_ROOT}/gateway/${modelFile}" ]; then
      echo "model is not configured, so call config-app first."
      return 1
    fi
    buildApp "${DATA_ROOT}/gateway/${modelFile}" ${modelName}
    if [ -f "${SCRIPT_DIR}/${modelName}_linux_amd64" ]; then
      ${sumv} "${SCRIPT_DIR}/${modelName}_linux_amd64" "${DATA_ROOT}/gateway/${modelName}_linux_amd64"
    else
      echo "failed to build ${modelName}_linux_amd64"
      return 1
    fi
  fi

  echo "start app service ${modelName}"
  kubectl create -f ${DATA_ROOT}/gateway/k8s/${modelName}-pv.yaml
  kubectl create -f ${DATA_ROOT}/gateway/k8s/${modelName}.yaml
  if [ "${ENV_TYPE}" == "k8s" ]; then
    # find auto-generated nodePort for local service
    local np=$(kubectl get service ${modelName} -o=jsonpath='{.spec.ports[0].nodePort}')
    echo "access ${modelName} service at http://localhost:${np}"
  elif [ "${ENV_TYPE}" == "aws" ]; then
    # update the sg for app-service
    ${SCRIPT_DIR}/../aws/setup-service-sg.sh ${ORG} ${modelName} ${PORT}
  elif [ "${ENV_TYPE}" == "az" ] || [ "${ENV_TYPE}" == "gcp" ]; then
    # wait for load-balancer to start
    local lbip=$(kubectl get service ${modelName} -n ${ORG} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
    local cnt=1
    until [ ! -z "${lbip}" ] || [ ${cnt} -gt 20 ]; do
      sleep 5s
      echo -n "."
      lbip=$(kubectl get service ${modelName} -n ${ORG} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
      cnt=$((${cnt}+1))
    done
    if [ -z "${lbip}" ]; then
      echo "cannot find k8s ${modelName} service for org: ${ORG}"
    else
      # TODO: display correct loadbalancer port
      local np=$(kubectl get service ${modelName} -o=jsonpath='{.spec.ports[0].port}')
      echo "access ${modelName} servcice at http://${lbip}:${np}"
    fi
  fi
}

function shutdownApp {
  local modelFile=${MODEL##*/}
  local modelName=${modelFile%.*}
  modelName=${modelName//_/-}
  echo "stop ${modelName} service ..."
  kubectl delete -f ${DATA_ROOT}/gateway/k8s/${modelName}.yaml
  kubectl delete -f ${DATA_ROOT}/gateway/k8s/${modelName}-pv.yaml
}

# replace network config in an app model with specified Fabric network yaml
# e.g., setNetworkConfig <model-json> <network-yaml>
function setNetworkConfig {
  # verify network config file
  if [ ! -f "${2}" ]; then
    # network config file not found print original model-json
    cat ${1}
    return 1
  fi
  local configName="${2##*/}"
  local content=$(cat ${2} | base64 | tr -d \\n)

  # print updated model json
  cat ${1} | jq 'walk(if type == "object" and has("name") and .name == "config" then walk(if type == "object" and has("content") then {"filename":"'${configName}'", "content": "data:application/x-yaml;base64,'${content}'"} else . end) else . end)'
}

# replace entity matcher in an app model with specified entity matcher yaml
# e.g., setEntityMatcher <model-json> [<matcher-yaml>]
function setEntityMatcher {
  # verify entity matcher file
  local matcherName=""
  local content=$(echo "entityMatchers:" | base64 | tr -d \\n)
  if [ ! -z "${2}" ]; then
    if [ -f "${2}" ]; then
      matcherName="${2##*/}"
      content=$(cat ${2} | base64 | tr -d \\n)
    fi
  fi

  # print updated model json
  cat ${1} | jq 'walk(if type == "object" and has("name") and .name == "entityMatcher" then walk(if type == "object" and has("content") then {"filename":"'${matcherName}'", "content": "data:application/x-yaml;base64,'${content}'"} else . end) else . end)'
}

###############################################################################
# configure client app as Kubernetes service
###############################################################################

# set list of orderers from config
function getOrderers {
  ORDERERS=()
  local seq=${ORDERER_MIN:-"0"}
  local max=${ORDERER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    ORDERERS+=("orderer-${seq}")
    seq=$((${seq}+1))
  done
}

# set list of peers from config
function getPeers {
  PEERS=()
  local seq=${PEER_MIN:-"0"}
  local max=${PEER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    PEERS+=("peer-${seq}")
    seq=$((${seq}+1))
  done
}

# e.g., getHostUrl peer-1
function getHostUrl {
  if [ ! -z "${SVC_DOMAIN}" ]; then
    # for Kubernetes target
    svc=${1%%-*}
    echo "${1}.${svc}.${SVC_DOMAIN}"
  else
    # default for docker-composer
    echo "${1}.${FABRIC_ORG}"
  fi
}

# printNetworkYaml <channel>
function printNetworkYaml {
  getOrderers
  getPeers
  local caHost="ca-server.${FABRIC_ORG}"
  if [ ! -z "${SVC_DOMAIN}" ]; then
    caHost="ca-server.${SVC_DOMAIN}"
  fi
  echo "
name: ${1}
version: 1.0.0

client:
  organization: ${ORG}
  logging:
    level: info
  cryptoconfig:
    path: \${CRYPTO_PATH}

channels:
  ${1}:
    peers:"
  for p in "${PEERS[@]}"; do
    echo "
      ${p}.${FABRIC_ORG}:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true"
  done
  echo "
organizations:
  ${ORG}:
    mspid: ${ORG_MSP}
    cryptoPath:  ${FABRIC_ORG}/users/{username}@${FABRIC_ORG}/msp
    peers:"
  for p in "${PEERS[@]}"; do
    echo "      - ${p}.${FABRIC_ORG}"
  done
  echo "    certificateAuthorities:
      - ca.${FABRIC_ORG}

orderers:"
  for ord in "${ORDERERS[@]}"; do
    echo "
  ${ord}.${FABRIC_ORG}:
    url: $(getHostUrl ${ord}):7050
    tlsCACerts:
      path: \${CRYPTO_PATH}/${FABRIC_ORG}/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem"
  done
  echo "
peers:"
  for p in "${PEERS[@]}"; do
    echo "
  ${p}.${FABRIC_ORG}:
    url: $(getHostUrl ${p}):7051
    tlsCACerts:
      path: \${CRYPTO_PATH}/${FABRIC_ORG}/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem"
  done
  echo "
certificateAuthorities:
  ca.${FABRIC_ORG}:
    url: https://${caHost}:7054
    tlsCACerts:
      path: \${CRYPTO_PATH}/${FABRIC_ORG}/ca/tls/server.crt
    registrar:
      enrollId: ${CA_ADMIN:-"caadmin"}
      enrollSecret: ${CA_PASSWD:-"caadminpw"}
    caName: ca.${FABRIC_ORG}"
}

# print k8s persistent volume for client-app config files
# e.g., printDataPV <appName>
function printDataPV {
  local _store_size="${TOOL_PV_SIZE}"
  local _mode="ReadWriteOnce"
  local _folder="gateway"

  echo "---
kind: PersistentVolume
apiVersion: v1
metadata:
  name: data-${ORG}-${1}
  labels:
    app: data-${1}
    org: ${ORG}
spec:
  capacity:
    storage: ${_store_size}
  volumeMode: Filesystem
  accessModes:
  - ${_mode}
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ${ORG}-${1}-data-class"

  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    echo "  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${AWS_FSID}
    volumeAttributes:
      path: /${FABRIC_ORG}/${_folder}"
  elif [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo "  azureFile:
    secretName: azure-secret
    shareName: ${AZ_STORAGE_SHARE}/${FABRIC_ORG}/${_folder}
    readOnly: false
  mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=10000
  - gid=10000
  - mfsymlinks
  - nobrl"
  elif [ "${K8S_PERSISTENCE}" == "gfs" ]; then
    echo "  nfs:
    server: ${GCP_STORE_IP}
    path: /vol1/${FABRIC_ORG}/${_folder}"
  else
    echo "  hostPath:
    path: ${DATA_ROOT}/${_folder}
    type: Directory"
  fi

  echo "---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: data-${1}
  namespace: ${ORG}
spec:
  storageClassName: ${ORG}-${1}-data-class
  accessModes:
    - ${_mode}
  resources:
    requests:
      storage: ${_store_size}
  selector:
    matchLabels:
      app: data-${1}
      org: ${ORG}"
}

# printStorageClass <appName>
# storage class for local host, or AWS EFS, or Azure Files
function printStorageClass {
  local _provision="kubernetes.io/no-provisioner"
  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    _provision="efs.csi.aws.com"
  elif [ "${K8S_PERSISTENCE}" == "azf" ]; then
    _provision="kubernetes.io/azure-file"
  elif [ "${K8S_PERSISTENCE}" == "gfs" ]; then
    # no need to define storage class for Google Filestore
    return 0
  fi

  echo "
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: ${ORG}-${1}-data-class
provisioner: ${_provision}
volumeBindingMode: WaitForFirstConsumer"

  if [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo "parameters:
  skuName: Standard_LRS"
  fi
}

# printStorageYaml <appName>
function printStorageYaml {
  # storage class for client-app data folders
  printStorageClass ${1}

  # PV and PVC for client-app data
  printDataPV ${1}
}

# printAppYaml <appName>
function printAppYaml {
  local user=${USER_ID:-"Admin"}
  echo "
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${1}
  namespace: ${ORG}
  labels:
    app: ${1}
spec:
  replicas: 2
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: ${1}
  template:
    metadata:
      labels:
        app: ${1}
    spec:
      containers:
      - name: ${1}
        image: ubuntu:18.04
        resources:
          requests:
            memory: ${POD_MEM}
            cpu: ${POD_CPU}
        env:
        - name: CRYPTO_PATH
          value: /etc/hyperledger/gateway
        - name: PORT
          value: \"${PORT}\"
        - name: APPUSER
          value: ${user}
        - name: TLS_ENABLED
          value: \"false\"
        - name: FLOGO_APP_PROP_RESOLVERS
          value: env
        - name: FLOGO_APP_PROPS_ENV
          value: auto
        - name: FLOGO_LOG_LEVEL
          value: DEBUG
        - name: FLOGO_SCHEMA_SUPPORT
          value: \"true\"
        - name: FLOGO_SCHEMA_VALIDATION
          value: \"false\"
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        workingDir: /etc/hyperledger/gateway
        command: [\"./${1}_linux_amd64\"]
        ports:
        - containerPort: ${PORT}
          name: svc-port
        volumeMounts:
        - mountPath: /etc/hyperledger/gateway
          name: data
      restartPolicy: Always
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: data-${1}
---
apiVersion: v1
kind: Service
metadata:
  name: ${1}
  namespace: ${ORG}
spec:
  selector:
    app: ${1}"
  if [ "${ENV_TYPE}" == "k8s" ]; then
    echo "  ports:
  # use nodePort for Mac docker-desktop, port range must be 30000-32767
  - protocol: TCP
    name: svc-port
    port: ${PORT}
    targetPort: svc-port
    # nodePort: 30091
  type: NodePort"
  else
    echo "  ports:
  - protocol: TCP
    name: svc-port
    port: ${PORT}
    targetPort: svc-port
  type: LoadBalancer"
  fi
}

###############################################################################
# main commands
###############################################################################

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  dovetail.sh <cmd> [options]"
  echo "    <cmd> - one of the following commands"
  echo "      - 'install-fe' - install Flogo Enterprise from zip; arguments: -s <FE-installer-zip>"
  echo "      - 'build-cds' - build chaincode model to cds format; args; -s -j -c [-v]"
  echo "      - 'build-app' - upload and build fabric client app; args: -j -c -o [-a]"
  echo "      - 'config-app' - config client app with specified network and entity matcher yaml; args: -j [-i -n -u]"
  echo "      - 'start-app' - build and start kubernetes service for specified app model that is previously configured using config-app; args: -j"
  echo "      - 'stop-app' - shutdown kubernetes service for specified app model; args: -j"
  echo "    -p <property file> - the .env file in config folder that defines network properties, e.g., netop1 (default)"
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'"
  echo "    -s <source> - source folder name containing flogo model and other required files, e.g., ./marble"
  echo "    -j <json> - flogo model file in json format, e.g., marble.json"
  echo "    -c <cc-name> - chaincode or app name, e.g., marble_cc or marble_client"
  echo "    -v <version> - chaincode version, e.g., 1.0 (default)"
  echo "    -i <channel-id> - channel for client app to invoke chaincode"
  echo "    -n <port-number> - service listen port, e.g. '7091' (default)"
  echo "    -u <user> - user that client app uses to connect to fabric network, e.g. 'Admin' (default)"
  echo "    -o <GOOS> - os for app executable, e.g., darwin or linux (default)"
  echo "    -a <GOARCH> - hardware arch for app executable, e.g., amd64 (default)"
  echo "  dovetail.sh -h (print this message)"
}

ORG_ENV="netop1"

CMD=${1}
shift
while getopts "h?p:t:s:j:c:v:i:n:u:o:a:" opt; do
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
  i)
    CHANNEL_ID=$OPTARG
    ;;
  n)
    PORT=$OPTARG
    ;;
  u)
    USER_ID=$OPTARG
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
  fi
  if [ -z "${FE_HOME}" ]; then
    echo "FE_HOME is not defined"
  fi
else
  DT_HOME=${HOME}/dovetail-contrib/hyperledger-fabric
  if [ -d "${HOME}/flogo" ]; then
    FE_HOME=$(find ${HOME}/flogo -name ?.? -print)
  fi
fi

if [ -z "${CHANNEL_ID}" ]; then
  CHANNEL_ID=${TEST_CHANNEL}
fi
if [ -z "${USER_ID}" ]; then
  USER_ID=${ADMIN_USER:-"Admin"}
fi
if [ -z "${PORT}" ]; then
  PORT=7091
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
config-app)
  echo "config client app for model ${MODEL} with ${CHANNEL_ID} ${PORT} ${USER_ID}"
  if [ -z "${MODEL}" ] || [ ! -f "${MODEL}" ]; then
    echo "app moodel file must be specified and exist"
    exit 1
  fi
  configureApp
  ;;
start-app)
  echo "start kubernetes service for client app for model ${MODEL}"
  if [ -z "${MODEL}" ]; then
    echo "app model is not specified"
    exit 1
  fi
  startApp
  ;;
stop-app)
  echo "shutdown kubernetes service for client app for model ${MODEL}"
  if [ -z "${MODEL}" ]; then
    echo "app model is not specified"
    exit 1
  fi
  shutdownApp
  ;;
*)
  printHelp
  exit 1
esac
