#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# start or shutdown and config client gateway service
# usage: gateway.sh <cmd> [-p <property file>] [-t <env type>] [-c channel>] [-u <user>]
# it uses a property file of the specified org as defined in ../config/org.env, e.g.
#   gateway.sh start -p netop1
# would use config parameters specified in ../config/netop1.env
# the env_type can be k8s or aws/az/gcp to use local host or a cloud file system, i.e. efs/azf/gfs, default k8s for local persistence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"

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

function printLocalMatcherYaml {
  ORDERER_PORT=${ORDERER_PORT:-"7050"}
  PEER_PORT=${PEER_PORT:-"7051"}

  echo "entityMatchers:
  peer:"

  # peer name matchers
  local seq=${PEER_MIN:-"0"}
  local max=${PEER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    local p="peer-${seq}"
    local port=$((${seq} * 10 + ${PEER_PORT}))
    seq=$((${seq}+1))
    echo "
    - pattern: ${p}.${ORG}.(\w+)
      urlSubstitutionExp: localhost:${port}
      sslTargetOverrideUrlSubstitutionExp: ${p}.${FABRIC_ORG}
      mappedHost: ${p}.${FABRIC_ORG}"
  done

  # peer port matchers
  seq=${PEER_MIN:-"0"}
  max=${PEER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    local p="peer-${seq}"
    local port=$((${seq} * 10 + ${PEER_PORT}))
    seq=$((${seq}+1))
    echo "
    - pattern: (\w+):${port}
      urlSubstitutionExp: localhost:${port}
      sslTargetOverrideUrlSubstitutionExp: ${p}.${FABRIC_ORG}
      mappedHost: ${p}.${FABRIC_ORG}"
  done
  echo "
    - pattern: (\w+).${ORG}.(\w+):(\d+)
      urlSubstitutionExp: localhost:\${3}
      sslTargetOverrideUrlSubstitutionExp: \${1}.${FABRIC_ORG}
      mappedHost: \${1}.${FABRIC_ORG}

  orderer:"

  # orderer name matchers
  seq=${ORDERER_MIN:-"0"}
  max=${ORDERER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    local ord="orderer-${seq}"
    local port=$((${seq} * 10 + ${ORDERER_PORT}))
    seq=$((${seq}+1))
    echo "
    - pattern: ${ord}.${ORG}.(\w+)
      urlSubstitutionExp: localhost:${port}
      sslTargetOverrideUrlSubstitutionExp: ${ord}.${FABRIC_ORG}
      mappedHost: ${ord}.${FABRIC_ORG}"
  done

  # orderer port matchers
  seq=${ORDERER_MIN:-"0"}
  max=${ORDERER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    local ord="orderer-${seq}"
    local port=$((${seq} * 10 + ${ORDERER_PORT}))
    seq=$((${seq}+1))
    echo "
    - pattern: (\w+):${port}
      urlSubstitutionExp: localhost:${port}
      sslTargetOverrideUrlSubstitutionExp: ${ord}.${FABRIC_ORG}
      mappedHost: ${ord}.${FABRIC_ORG}"
  done

  echo "
    - pattern: (\w+).${ORG}.(\w+):(\d+)
      urlSubstitutionExp: localhost:\${3}
      sslTargetOverrideUrlSubstitutionExp: \${1}.${FABRIC_ORG}
      mappedHost: \${1}.${FABRIC_ORG}

  certificateAuthority:
    - pattern: (\w+).${ORG}.(\w+)
      urlSubstitutionExp: https://localhost:7054
      sslTargetOverrideUrlSubstitutionExp: ca-server.${FABRIC_ORG}
      mappedHost: ca-server.${FABRIC_ORG}"
}

##############################################################################
# Kubernetes functions
##############################################################################

# print k8s persistent volume for gateway config files
# e.g., printDataPV
function printDataPV {
  local _store_size="${TOOL_PV_SIZE}"
  local _mode="ReadWriteOnce"
  local _folder="gateway"

  echo "---
kind: PersistentVolume
apiVersion: v1
metadata:
  name: data-${ORG}-gateway
  labels:
    app: data-gateway
    org: ${ORG}
spec:
  capacity:
    storage: ${_store_size}
  volumeMode: Filesystem
  accessModes:
  - ${_mode}
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ${ORG}-gateway-data-class"

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
  name: data-gateway
  namespace: ${ORG}
spec:
  storageClassName: ${ORG}-gateway-data-class
  accessModes:
    - ${_mode}
  resources:
    requests:
      storage: ${_store_size}
  selector:
    matchLabels:
      app: data-gateway
      org: ${ORG}"
}

# printStorageClass
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
  name: ${ORG}-gateway-data-class
provisioner: ${_provision}
volumeBindingMode: WaitForFirstConsumer"

  if [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo "parameters:
  skuName: Standard_LRS"
  fi
}

function printStorageYaml {
  # storage class for gateway data folders
  printStorageClass

  # PV and PVC for gateway data
  printDataPV
}

# printGatewayYaml <channel> <user>
function printGatewayYaml {
  local user=${2:-"Admin"}
  echo "
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway
  namespace: ${ORG}
  labels:
    app: gateway
spec:
  replicas: 2
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: gateway
  template:
    metadata:
      labels:
        app: gateway
    spec:
      containers:
      - name: gateway
        image: ubuntu:18.04
        resources:
          requests:
            memory: ${POD_MEM}
            cpu: ${POD_CPU}
        env:
        - name: CONFIG_PATH
          value: /etc/hyperledger/gateway/config
        - name: CRYPTO_PATH
          value: /etc/hyperledger/gateway
        - name: GRPC_PORT
          value: \"7082\"
        - name: HTTP_PORT
          value: \"7081\"
        - name: TLS_ENABLED
          value: \"false\"
        - name: NETWORK_FILE
          value: \"config_${1}.yaml\"
        - name: ENTITY_MATCHER_FILE
          value: \"\"
        - name: CHANNEL_ID
          value: ${1}
        - name: USER_NAME
          value: ${user}
        - name: ORG
          value: ${ORG}
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        workingDir: /etc/hyperledger/gateway
        command: [\"./gateway\"]
        args: [\"-logtostderr\", \"-v\", \"2\"]
        ports:
        - containerPort: 7081
          name: http-port
        - containerPort: 7082
          name: grpc-port
        volumeMounts:
        - mountPath: /etc/hyperledger/gateway
          name: data
      restartPolicy: Always
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: data-gateway
---
apiVersion: v1
kind: Service
metadata:
  name: gateway
  namespace: ${ORG}
spec:
  selector:
    app: gateway"
  if [ "${ENV_TYPE}" == "k8s" ]; then
    echo "  ports:
  # use nodePort for Mac docker-desktop, port range must be 30000-32767
  - protocol: TCP
    name: http-port
    port: 7081
    targetPort: http-port
    nodePort: 30081
  - protocol: TCP
    name: grpc-port
    port: 7082
    targetPort: grpc-port
    nodePort: 30082
  type: NodePort"
  else
    echo "  ports:
  - protocol: TCP
    name: http-port
    port: 7081
    targetPort: http-port
  - protocol: TCP
    name: grpc-port
    port: 7082
    targetPort: grpc-port
  type: LoadBalancer"
  fi
}

##############################################################################
# Gateway operations
##############################################################################

function createArtifacts {
  if [ "${ENV_TYPE}" == "docker" ]; then
    echo "create network config for local host"
    printNetworkYaml ${CHANNEL_ID} > ${SCRIPT_DIR}/config/config_${CHANNEL_ID}.yaml
    printLocalMatcherYaml > ${SCRIPT_DIR}/config/matchers.yaml
  else
    echo "create network config"
    ${sumd} -p ${DATA_ROOT}/gateway/config
    printNetworkYaml ${CHANNEL_ID} | ${stee} ${DATA_ROOT}/gateway/config/config_${CHANNEL_ID}.yaml > /dev/null

    echo "create k8s yaml files"
    ${sumd} -p ${DATA_ROOT}/gateway/k8s
    printStorageYaml | ${stee} ${DATA_ROOT}/gateway/k8s/gateway-pv.yaml > /dev/null
    printGatewayYaml ${CHANNEL_ID} ${USER_ID} | ${stee} ${DATA_ROOT}/gateway/k8s/gateway.yaml > /dev/null
  fi
}

function startGateway {
  createArtifacts

  if [ "${ENV_TYPE}" == "docker" ]; then
    if [ -f ${SCRIPT_DIR}/gateway ]; then
      echo "start gateway service"
      cd ${SCRIPT_DIR}
      CRYPTO_PATH=${DATA_ROOT}/gateway ./gateway -network config_${CHANNEL_ID}.yaml -matcher matchers.yaml -org ${ORG} -logtostderr -v 2
    else
      echo "Cannot find gateway executable. Build it and then retry."
      return 1
    fi
  else
    if [ ! -f ${DATA_ROOT}/gateway/gateway ]; then
      if [ -f ${SCRIPT_DIR}/gateway-linux ]; then
        echo "copy gateway artifacts to ${DATA_ROOT}/gateway"
        ${sucp} ${SCRIPT_DIR}/gateway-linux ${DATA_ROOT}/gateway/gateway
        ${sucp} ${SCRIPT_DIR}/src/fabric.proto ${DATA_ROOT}/gateway
        ${sucp} -Rf ${SCRIPT_DIR}/swagger-ui ${DATA_ROOT}/gateway
      else
        echo "cannot find gateway executable 'gateway-linux'. Build it and then retry."
        return 1
      fi
    fi

    echo "start gateway service"
    kubectl create -f ${DATA_ROOT}/gateway/k8s/gateway-pv.yaml
    kubectl create -f ${DATA_ROOT}/gateway/k8s/gateway.yaml
    if [ "${ENV_TYPE}" == "k8s" ]; then
      echo "browse gateway REST swagger-ui at http://localhost:30081/swagger"
      echo "view gateway grpc service defintion at http://localhost:30081/doc"
    elif [ "${ENV_TYPE}" == "aws" ]; then
      ${SCRIPT_DIR}/../aws/setup-service-sg.sh ${ORG} "gateway"
    elif [ "${ENV_TYPE}" == "az" ] || [ "${ENV_TYPE}" == "gcp" ]; then
      # wait for load-balancer to start
      local lbip=$(kubectl get service gateway -n ${ORG} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
      local cnt=1
      until [ ! -z "${lbip}" ] || [ ${cnt} -gt 20 ]; do
        sleep 5s
        echo -n "."
        lbip=$(kubectl get service gateway -n ${ORG} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
        cnt=$((${cnt}+1))
      done
      if [ -z "${lbip}" ]; then
        echo "cannot find k8s gateway service for org: ${ORG}"
      else
        echo "browse gateway swagger UI at http://${lbip}:7081/swagger"
      fi
    fi
  fi
}

function shutdownGateway {
  if [ "${ENV_TYPE}" == "docker" ]; then
    echo "You can shutdown gateway by Ctrl+C"
  else
    echo "stop gateway service ..."
    kubectl delete -f ${DATA_ROOT}/gateway/k8s/gateway.yaml
    kubectl delete -f ${DATA_ROOT}/gateway/k8s/gateway-pv.yaml
  fi
}

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  gateway.sh <cmd> [-p <property file>] [-t <env type>] [-c channel>] [-u <user>]"
  echo "    <cmd> - one of the following commands:"
  echo "      - 'start' - start gateway service, arguments: [-p <prop-file>] [-t <env-type>] [-c channel>] [-u <user>]"
  echo "      - 'shutdown' - shutdown gateway service, arguments: [-p <prop-file>] [-t <env-type>]"
  echo "      - 'config' - create gateway artifacts, arguments: [-p <prop-file>] [-t <env-type>] [-c channel>] [-u <user>]"
  echo "    -p <property file> - the .env file in config folder that defines network properties, e.g., netop1 (default)"
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'"
  echo "    -c <channel> - default channel ID that the gateway will connect to, default 'mychannel'"
  echo "    -u <user> - default user that the gateway will use to connect to fabric network, default 'Admin'"
  echo "  gateway.sh -h (print this message)"
}

ORG_ENV="netop1"

CMD=${1}
shift
while getopts "h?p:t:c:u:" opt; do
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
  u)
    USER_ID=$OPTARG
    ;;
  c)
    CHANNEL_ID=$OPTARG
    ;;
  esac
done

source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORG_ENV} ${ENV_TYPE}
if [ "${USER_ID}" == "" ]; then
  USER_ID=${ADMIN_USER:-"Admin"}
fi
if [ "${CHANNEL_ID}" == "" ]; then
  CHANNEL_ID=${TEST_CHANNEL:-"mychannel"}
fi

case "${CMD}" in
start)
  echo "start gateway service: ${ORG_ENV} ${ENV_TYPE}"
  startGateway
  ;;
shutdown)
  echo "shutdown gateway service: ${ORG_ENV} ${ENV_TYPE} ${CHANNEL_ID} ${USER_ID}"
  shutdownGateway
  ;;
config)
  echo "config gateway service: ${ORG_ENV} ${ENV_TYPE} ${CHANNEL_ID} ${USER_ID}"
  createArtifacts
  ;;
*)
  printHelp
  exit 1
esac
