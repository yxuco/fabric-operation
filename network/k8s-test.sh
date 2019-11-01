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

# printCliPV artifacts|crypto|chaincode
function printCliPV {
    if [ "${1}" == "artifacts" ]; then
    FOLDER="artifacts"
  elif [ "${1}" == "crypto" ]; then
    FOLDER="crypto/cli"
  else
    # chaincode
    FOLDER="chaincode"
  fi

  echo "---
kind: PersistentVolume
apiVersion: v1
metadata:
  name: ${1}-cli
  labels:
    app: ${1}-cli
    org: ${ORG}
spec:
  capacity:
    storage: 100Mi
  volumeMode: Filesystem
  accessModes:
  - ReadOnlyMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: cli-data-class"

  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    echo "  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${AWS_FSID}
    volumeAttributes:
      path: /${FABRIC_ORG}/${FOLDER}"
  else
    echo "  hostPath:
    path: ${DATA_ROOT}/${FOLDER}
    type: Directory"
  fi

  echo "---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ${1}-cli
  namespace: ${ORG}
spec:
  storageClassName: cli-data-class
  accessModes:
    - ReadOnlyMany
  resources:
    requests:
      storage: 100Mi
  selector:
    matchLabels:
      app: ${1}-cli
      org: ${ORG}"
}

# printStorageClass <name>
# storage class for local host, or AWS EFS
function printStorageClass {
  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    PROVISIONER="efs.csi.aws.com"
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
volumeBindingMode: WaitForFirstConsumer
"
}

function printCliStorageYaml {
  # storage class for cli data folders
  printStorageClass "cli-data-class"

  # PV and PVC for cli data
  printCliPV artifacts
  printCliPV crypto
  printCliPV chaincode
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
    - bash
    - -c
    - \"while true; do sleep 30; done\"
    env:
    - name: CORE_PEER_ADDRESS
      value: ${1}.peer.${SVC_DOMAIN}:7051
    - name: CORE_PEER_ID
      value: cli
    - name: CORE_PEER_LOCALMSPID
      value: ${ORG_MSP}
    - name: CORE_PEER_MSPCONFIGPATH
      value: /etc/hyperledger/cli/crypto/${admin}@${FABRIC_ORG}/msp
    - name: CORE_PEER_TLS_CERT_FILE
      value: /etc/hyperledger/cli/crypto/${1}.${FABRIC_ORG}/tls/server.crt
    - name: CORE_PEER_TLS_ENABLED
      value: \"true\"
    - name: CORE_PEER_TLS_KEY_FILE
      value: /etc/hyperledger/cli/crypto/${1}.${FABRIC_ORG}/tls/server.key
    - name: CORE_PEER_TLS_ROOTCERT_FILE
      value: /etc/hyperledger/cli/crypto/${1}.${FABRIC_ORG}/tls/ca.crt
    - name: CORE_VM_ENDPOINT
      value: unix:///host/var/run/docker.sock
    - name: FABRIC_LOGGING_SPEC
      value: INFO
    - name: GOPATH
      value: /opt/gopath
    - name: ORDERER_CA
      value: /etc/hyperledger/cli/crypto/${TEST_ORDERER}.${FABRIC_ORG}/msp/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem
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
    workingDir: /etc/hyperledger/cli/artifacts
    volumeMounts:
    - mountPath: /host/var/run
      name: docker-sock
    - mountPath: /etc/hyperledger/cli/artifacts
      name: artifacts
    - mountPath: /opt/gopath/src/github.com/chaincode
      name: chaincode
    - mountPath: /etc/hyperledger/cli/crypto
      name: crypto
  volumes:
  - name: docker-sock
    hostPath:
      path: /var/run
      type: Directory
  - name: artifacts
    persistentVolumeClaim:
      claimName: artifacts-cli
  - name: crypto
    persistentVolumeClaim:
      claimName: crypto-cli
  - name: chaincode
    persistentVolumeClaim:
      claimName: chaincode-cli"
}

function main {
  echo "generate k8s yaml for cli"
  TEST_ORDERER=orderer-0
  printCliStorageYaml > ${DATA_ROOT}/network/k8s/cli-pv.yaml
  printCliYaml peer-0 > ${DATA_ROOT}/network/k8s/cli.yaml

  # copy test chaincode
  local chaincode=$(dirname "${SCRIPT_DIR}")/chaincode
  if [ -d "${chaincode}" ]; then
    echo "copy chaincode from ${chaincode}"
    cp -R ${chaincode} ${DATA_ROOT}
  fi

  # copy test-sample script to artifacts
  if [ -f "${SCRIPT_DIR}/test-sample.sh" ]; then
    echo "copy smoke test script ${SCRIPT_DIR}/test-sample.sh"
    cp ${SCRIPT_DIR}/test-sample.sh ${DATA_ROOT}/artifacts
  fi

  echo "start cli POD"
  kubectl create -f ${DATA_ROOT}/network/k8s/cli-pv.yaml
  kubectl create -f ${DATA_ROOT}/network/k8s/cli.yaml

  echo "wait 15s for cli pod to start ..."
  sleep 15
  kubectl exec -it cli -- bash -c '/etc/hyperledger/cli/artifacts/test-sample.sh'
}

main
