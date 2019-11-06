#!/bin/bash
# execute smoke test for kubernetes docker-desktop on fabric network for a specified org
# usage: k8s-test.sh <org_name> <env>
# where config parameters for the org are specified in ../config/org.env, e.g.
#   k8s-test.sh netop1
# use config parameters specified in ../config/netop1.env
# second parameter env can be k8s or aws to use local host or efs persistence, default k8s for local persistence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
ENV_TYPE=${2:-"k8s"}
source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${1:-"netop1"} ${ENV_TYPE}

ORG_MSP=${ORG}MSP
SYS_CHANNEL=${SYS_CHANNEL:-"${ORG}-channel"}
TEST_CHANNEL=${TEST_CHANNEL:-"mychannel"}
ORDERER_TYPE=${ORDERER_TYPE:-"solo"}

# printDataPV "data-cli"
function printDataPV {

  echo "---
kind: PersistentVolume
apiVersion: v1
metadata:
  name: ${1}-pv
  labels:
    app: ${1}
    org: ${ORG}
spec:
  capacity:
    storage: 100Mi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: cli-data-class"

  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    echo "  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${AWS_FSID}
    volumeAttributes:
      path: /${FABRIC_ORG}/cli"
  elif [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo"  azureFile:
    secretName: azure-secret
    shareName: ${AZ_STORAGE_SHARE}/${FABRIC_ORG}/cli
    readOnly: false
  mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=10000
  - gid=10000
  - mfsymlinks
  - nobrl"
  else
    echo "  hostPath:
    path: ${DATA_ROOT}/cli
    type: Directory"
  fi

  echo "---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ${1}-pvc
  namespace: ${ORG}
spec:
  storageClassName: cli-data-class
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
  selector:
    matchLabels:
      app: ${1}
      org: ${ORG}"
}

# printStorageClass <name>
# storage class for local host, or AWS EFS
function printStorageClass {
  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    PROVISIONER="efs.csi.aws.com"
  elif [ "${K8S_PERSISTENCE}" == "azf" ]; then
    PROVISIONER="kubernetes.io/azure-file"
  else
    # default to local host
    PROVISIONER="kubernetes.io/no-provisioner"
  fi

  echo "
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: ${1}
provisioner: ${PROVISIONER}
volumeBindingMode: WaitForFirstConsumer"

  if [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo "parameters:
  skuName: Standard_LRS"
  fi
}

function printCliStorageYaml {
  # storage class for cli data folders
  printStorageClass "cli-data-class"

  # PV and PVC for cli data
  printDataPV "data-cli"
}

# printCliYaml <test-peer>
# e.g., printCliYaml peer-0
function printCliYaml {
  admin=${ADMIN_USER:-"Admin"}
  echo "
apiVersion: v1
kind: Pod
metadata:
  name: cli
  namespace: ${ORG}
spec:
  containers:
  - name: cli
    image: hyperledger/fabric-tools
    imagePullPolicy: Always
    command:
    - /bin/bash
    - -c
    - |
      mkdir -p /opt/gopath/src/github.com
      cp -R /etc/hyperledger/cli/store/chaincode /opt/gopath/src/github.com
      while true; do sleep 30; done
    env:
    - name: CORE_PEER_ADDRESS
      value: ${1}.peer.${SVC_DOMAIN}:7051
    - name: CORE_PEER_ID
      value: cli
    - name: CORE_PEER_LOCALMSPID
      value: ${ORG_MSP}
    - name: CORE_PEER_MSPCONFIGPATH
      value: /etc/hyperledger/cli/store/crypto/${admin}@${FABRIC_ORG}/msp
    - name: CORE_PEER_TLS_CERT_FILE
      value: /etc/hyperledger/cli/store/crypto/${1}/tls/server.crt
    - name: CORE_PEER_TLS_ENABLED
      value: \"true\"
    - name: CORE_PEER_TLS_KEY_FILE
      value: /etc/hyperledger/cli/store/crypto/${1}/tls/server.key
    - name: CORE_PEER_TLS_ROOTCERT_FILE
      value: /etc/hyperledger/cli/store/crypto/${1}/tls/ca.crt
    - name: CORE_VM_ENDPOINT
      value: unix:///host/var/run/docker.sock
    - name: FABRIC_LOGGING_SPEC
      value: INFO
    - name: GOPATH
      value: /opt/gopath
    - name: ORDERER_CA
      value: /etc/hyperledger/cli/store/crypto/${TEST_ORDERER}/msp/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem
    - name: ORDERER_TYPE
      value: ${ORDERER_TYPE}
    - name: ORDERER_URL
      value: ${TEST_ORDERER}.orderer.${SVC_DOMAIN}:7050
    - name: ORG
      value: ${ORG}
    - name: SYS_CHANNEL
      value: ${SYS_CHANNEL}
    - name: TEST_CHANNEL
      value: ${TEST_CHANNEL}
    workingDir: /etc/hyperledger/cli/store
    volumeMounts:
    - mountPath: /host/var/run
      name: docker-sock
    - mountPath: /etc/hyperledger/cli/store
      name: data
  volumes:
  - name: docker-sock
    hostPath:
      path: /var/run
      type: Directory
  - name: data
    persistentVolumeClaim:
      claimName: data-cli-pvc"
}

function main {
  echo "generate k8s yaml for cli"
  TEST_ORDERER=orderer-0
  printCliStorageYaml | ${stee} ${DATA_ROOT}/network/k8s/cli-pv.yaml > /dev/null
  printCliYaml peer-0 | ${stee} ${DATA_ROOT}/network/k8s/cli.yaml > /dev/null

  # copy test chaincode
  local chaincode=$(dirname "${SCRIPT_DIR}")/chaincode
  if [ -d "${chaincode}" ]; then
    echo "copy chaincode from ${chaincode}"
    ${sucp} -R ${chaincode} ${DATA_ROOT}/cli
  fi

  # copy test-sample script to artifacts
  if [ -f "${SCRIPT_DIR}/test-sample.sh" ]; then
    echo "copy smoke test script ${SCRIPT_DIR}/test-sample.sh"
    ${sucp} ${SCRIPT_DIR}/test-sample.sh ${DATA_ROOT}/cli
  fi

  # copy channel tx
  if [ -f "${DATA_ROOT}/tool/channel.tx" ]; then
    echo "copy channel tx from ${DATA_ROOT}/tool/channel.tx"
    ${sucp} ${DATA_ROOT}/tool/channel.tx ${DATA_ROOT}/cli
    ${sucp} ${DATA_ROOT}/tool/anchors.tx ${DATA_ROOT}/cli
  fi

  echo "start cli POD"
  kubectl create -f ${DATA_ROOT}/network/k8s/cli-pv.yaml
  kubectl create -f ${DATA_ROOT}/network/k8s/cli.yaml

  echo "wait 15s for cli pod to start ..."
  sleep 15
  kubectl exec -it cli -- bash -c './test-sample.sh'
}

main
