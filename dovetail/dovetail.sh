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
  # override flogo version for core and flow
  go mod edit -replace=github.com/project-flogo/core@v0.10.1=github.com/project-flogo/core@$(FLOGO_VER)
  go mod edit -replace=github.com/project-flogo/flow@v0.10.0=github.com/project-flogo/flow@$(FLOGO_VER)
  # avoid bug in activity/subflow/v0.9.0
  go get -u -d github.com/project-flogo/flow/activity/subflow@master
  go mod vendor
  # patch of flogo core and flow for handling chaincode
  cp -Rf ${DT_HOME}/flogo-patch/flow vendor/github.com/project-flogo
  cp -Rf ${DT_HOME}/flogo-patch/core vendor/github.com/project-flogo
  # work around issue of legacy bridge -- legacy bridge no longer needed
  # find vendor/github.com/TIBCOSoftware/dovetail-contrib/hyperledger-fabric/fabric/ -name '*_metadata.go' -exec rm {} \;
  echo "build ${chaincode}/${ccName}/${ccName} ..."
  env GOOS=linux GOARCH=amd64 go build -mod vendor -o ../${ccName}

  if [ ! -f "../${ccName}" ]; then
    echo "Failed to build ${ccName}"
    return 1
  fi

  # build cds -- Note: on bastion host, this can be replaced by localPackCDS
  packCDS ${ccName} ${version}
  
  local cds="${DATA_ROOT}/cli/${ccName}_${version}.cds"
  if [ -f "${cds}" ]; then
    echo "created cds: ${cds}"
  else
    echo "Failed to create CDS for chaincode in folder ${chaincode}/${ccName}"
    return 1
  fi
}

# create cds package using peer container, e.g. 
# packCDS <ccName> <version>
function packCDS {
  cd $(dirname "${SCRIPT_DIR}")/network
  ./network.sh package-chaincode -n peer-0 -f ${1}/src -s ${1} -v ${2}
}

# create cds package on bastion host locally, e.g. 
# localPackCDS <ccName> <version>
function localPackCDS {
  mkdir -p ${GOPATH}/src/github.com/chaincode
  rm -Rf ${GOPATH}/src/github.com/chaincode/${1}
  cp -R $(dirname "${SCRIPT_DIR}")/chaincode/${1}/src ${GOPATH}/src/github.com/chaincode/${1}
  # chaincode package command requires $FABRIC_CFG_PATH containing core.yaml and peer's msp cert/keys
  local cfgPath=${DATA_ROOT}/peers/peer-0/crypto
  sudo cp $(dirname "${SCRIPT_DIR}")/network/core.yaml ${cfgPath}
  FABRIC_CFG_PATH=${cfgPath} ${HOME}/fabric-samples/bin/peer chaincode package -n ${1} -v ${2} -l golang -p github.com/chaincode/${1} ${1}_${2}.cds
  sudo mv ${1}_${2}.cds ${DATA_ROOT}/cli
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
  # work around issue of legacy bridge -- legacy bridge no longer needed
  # find vendor/github.com/TIBCOSoftware/dovetail-contrib/hyperledger-fabric/fabclient/ -name '*_metadata.go' -exec rm {} \;
  env GOOS=${bOS} GOARCH=${bArch} go build -mod vendor -o ${SCRIPT_DIR}/${appName}_${bOS}_${bArch}

  local app="${SCRIPT_DIR}/${appName}_${bOS}_${bArch}"
  if [ -f "${app}" ]; then
    echo "created app: ${app}"
  else
    echo "Failed to create app for model ${model}"
    return 1
  fi
}

# edit flogo model json to use gateway network config
# write result model json in DATA_ROOT/tool
function configureApp {
  local network="${DATA_ROOT}/gateway/config/config_${CHANNEL_ID}.yaml"
  if [ ! -f "${network}" ]; then
    echo "config ${network} file not found, create it by using '../service/gateway.sh config -p ${ORG_ENV} -c ${CHANNEL_ID}'"
    return 1
  fi

  local modelFile=${MODEL##*/}
  local modelName=${modelFile%.*}
  modelName=${modelName//_/-}
  echo "config client app for model ${MODEL} with ${network}"
  setNetworkConfig "${MODEL}" "${network}" > ${MODEL}.tmp
  setEntityMatcher "${MODEL}.tmp" | ${stee} ${DATA_ROOT}/tool/${modelFile} > /dev/null
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
    if [ ! -f "${DATA_ROOT}/tool/${modelFile}" ]; then
      echo "model is not configured, so call config-app first."
      return 1
    fi
    if [ ! -f "${DATA_ROOT}/tool/${modelName}_linux_amd64" ]; then
      ${SCRIPT_DIR}/../msp/msp-util.sh build-app -p ${ORG_ENV} -t ${ENV_TYPE} -m "${DATA_ROOT}/tool/${modelFile}"
    fi
    if [ ! -f "${DATA_ROOT}/tool/${modelName}_linux_amd64" ]; then
      echo "failed to build ${modelName}_linux_amd64"
      return 1
    fi
    ${sumv} ${DATA_ROOT}/tool/${modelName}_linux_amd64 ${DATA_ROOT}/gateway/${modelName}_linux_amd64
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
  echo "      - 'config-app' - config client app with specified network and entity matcher yaml; args: -m [-i -n -u]"
  echo "      - 'start-app' - build and start kubernetes service for specified app model that is previously configured using config-app; args: -m"
  echo "      - 'stop-app' - shutdown kubernetes service for specified app model; args: -m"
  echo "    -p <property file> - the .env file in config folder that defines network properties, e.g., netop1 (default)"
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'"
  echo "    -s <source> - Flogo enterprise install zip file"
  echo "    -m <json> - flogo model file in json format, e.g., marble.json"
  echo "    -i <channel-id> - channel for client app to invoke chaincode"
  echo "    -n <port-number> - service listen port, e.g. '7091' (default)"
  echo "    -u <user> - user that client app uses to connect to fabric network, e.g. 'Admin' (default)"
  echo "  dovetail.sh -h (print this message)"
}

ORG_ENV="netop1"

CMD=${1}
shift
while getopts "h?p:t:s:m:i:n:u:" opt; do
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
  m)
    MODEL=$OPTARG
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
