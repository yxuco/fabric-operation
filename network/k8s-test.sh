#!/bin/bash
# execute smoke test for kubernetes docker-desktop on fabric network for a specified org
# usage: k8s-test.sh <org_name>
# where config parameters for the org are specified in ../config/org.env, e.g.
#   k8s-test.sh netop1
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source ${SCRIPT_DIR}/setup.sh ${1:-"netop1"} k8s

MSP_DIR=$(dirname "${SCRIPT_DIR}")/${FABRIC_ORG}
ORG_MSP=${ORG}MSP
SYS_CHANNEL=${SYS_CHANNEL:-"${ORG}-channel"}
TEST_CHANNEL=${TEST_CHANNEL:-"mychannel"}
ORDERER_TYPE=${ORDERER_TYPE:-"solo"}

# set list of peers from config
function getPeers {
  PEERS=()
  seq=${PEER_MIN:-"0"}
  max=${PEER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    PEERS+=("peer-${seq}")
    seq=$((${seq}+1))
  done
}

# printCliYaml <test-peer>
# e.g., printCliYaml peer-0
function printCliYaml {

  echo "
kind: PersistentVolume
apiVersion: v1
# config data for cli
metadata:
  name: config-cli
  labels:
    app: cli
    org: ${ORG}
spec:
  capacity:
    storage: 100Mi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: ${MSP_DIR}/k8s/cli
    type: Directory
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: config-cli
  namespace: ${ORG}
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
  selector:
    matchLabels:
      app: cli
      org: ${ORG}
---
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
      value: /etc/hyperledger/cli/config/${ADMIN}@${FABRIC_ORG}/msp
    - name: CORE_PEER_TLS_CERT_FILE
      value: /etc/hyperledger/cli/config/${1}.${FABRIC_ORG}/tls/server.crt
    - name: CORE_PEER_TLS_ENABLED
      value: \"true\"
    - name: CORE_PEER_TLS_KEY_FILE
      value: /etc/hyperledger/cli/config/${1}.${FABRIC_ORG}/tls/server.key
    - name: CORE_PEER_TLS_ROOTCERT_FILE
      value: /etc/hyperledger/cli/config/${1}.${FABRIC_ORG}/tls/ca.crt
    - name: CORE_VM_ENDPOINT
      value: unix:///host/var/run/docker.sock
    - name: FABRIC_LOGGING_SPEC
      value: INFO
    - name: GOPATH
      value: /opt/gopath
    - name: ORDERER_CA
      value: /etc/hyperledger/cli/config/${TEST_ORDERER}.${FABRIC_ORG}/msp/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem
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
    workingDir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    volumeMounts:
    - mountPath: /host/var/run
      name: docker-sock
    - mountPath: /etc/hyperledger/cli/config
      name: config
  volumes:
  - name: docker-sock
    hostPath:
      path: /var/run
      type: Directory
  - name: config
    persistentVolumeClaim:
      claimName: config-cli"
}

function setupTestConfig {
  mkdir -p ${MSP_DIR}/k8s/cli/${TEST_ORDERER}.${FABRIC_ORG}/msp
  cp -R ${MSP_DIR}/orderers/${TEST_ORDERER}.${FABRIC_ORG}/msp/tlscacerts ${MSP_DIR}/k8s/cli/${TEST_ORDERER}.${FABRIC_ORG}/msp

  for p in "${PEERS[@]}"; do
    mkdir -p ${MSP_DIR}/k8s/cli/${p}.${FABRIC_ORG}
    cp -R ${MSP_DIR}/peers/${p}.${FABRIC_ORG}/tls ${MSP_DIR}/k8s/cli/${p}.${FABRIC_ORG}
  done

  mkdir -p ${MSP_DIR}/k8s/cli/${ADMIN}\@${FABRIC_ORG}
  cp -R ${MSP_DIR}/users/${ADMIN}\@${FABRIC_ORG}/msp ${MSP_DIR}/k8s/cli/${ADMIN}\@${FABRIC_ORG}
  mkdir -p ${MSP_DIR}/k8s/cli/artifacts
  cp ${MSP_DIR}/artifacts/*.tx ${MSP_DIR}/k8s/cli/artifacts
  cp -R ${MSP_DIR}/../chaincode ${MSP_DIR}/k8s/cli
}

function main {
  TEST_ORDERER=orderer-0
  ADMIN=${ADMIN_USER:-"Admin"}
  getPeers
  setupTestConfig
  printCliYaml peer-0 > ${MSP_DIR}/network/k8s-cli.yaml

  cp ${SCRIPT_DIR}/k8s-test-sample.sh ${MSP_DIR}/k8s/cli
  kubectl create -f ${MSP_DIR}/network/k8s-cli.yaml

  echo "wait 15s for cli pod to start ..."
  sleep 15
  kubectl exec -it cli -- bash -c '/etc/hyperledger/cli/config/k8s-test-sample.sh'
}

main
