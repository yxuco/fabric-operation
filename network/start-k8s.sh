#!/bin/bash
# create and start fabric network for Mac docker-desktop Kubernetes
# usage: start-k8s.sh <org_name> <env>
# it uses config parameters of the specified org as defined in ../config/org.env, e.g.
#   start-k8s.sh netop1
# using config parameters specified in ../config/netop1.env
# second parameter env can be k8s or aws to use local host or efs persistence, default k8s for local persistence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
ENV_TYPE=${2:-"k8s"}
source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${1:-"netop1"} ${ENV_TYPE}

ORG_MSP="${ORG}MSP"
ORDERER_MSP=${ORDERER_MSP:-"${ORG}OrdererMSP"}

SYS_CHANNEL=${SYS_CHANNEL:-"${ORG}-channel"}
TEST_CHANNEL=${TEST_CHANNEL:-"mychannel"}
ORDERER_TYPE=${ORDERER_TYPE:-"solo"}
COUCHDB_USER=${COUCHDB_USER:-""}
COUCHDB_PASSWD=${COUCHDB_PASSWD:-""}

# set list of orderers from config
function getOrderers {
  ORDERERS=()
  seq=${ORDERER_MIN:-"0"}
  max=${ORDERER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    ORDERERS+=("orderer-${seq}")
    seq=$((${seq}+1))
  done
}

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

# print k8s persistent volume for an orderer or peer
# even though volumeClaimTemplates can generate PVC automatically, 
# we define all PVCs here to guarantee that they match the corresponding PVs
# e.g., printDataPV "orderer-1" "orderer-data-class"
function printDataPV {
  STORAGE="500Mi"
  PATH_TYPE="Directory"
  MODE="ReadWriteOnce"
  if [ "${2}" == "orderer-data-class" ]; then
    FOLDER="orderers/${1}"
  elif [ "${2}" == "peer-data-class" ]; then
    FOLDER="peers/${1}"
  fi

  echo "---
kind: PersistentVolume
apiVersion: v1
metadata:
  name: data-${1}
  labels:
    app: data-${1}
    org: ${ORG}
spec:
  capacity:
    storage: ${STORAGE}
  volumeMode: Filesystem
  accessModes:
  - ${MODE}
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ${2}"

  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    echo "  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${AWS_FSID}
    volumeAttributes:
      path: /${FABRIC_ORG}/${FOLDER}"
  elif [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo"  azureFile:
    secretName: azure-secret
    shareName: ${AZ_STORAGE_SHARE}/${FABRIC_ORG}/${FOLDER}
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
    path: ${DATA_ROOT}/${FOLDER}
    type: ${PATH_TYPE}"
  fi

  echo "---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: data-${1}
  namespace: ${ORG}
spec:
  storageClassName: ${2}
  accessModes:
    - ${MODE}
  resources:
    requests:
      storage: ${STORAGE}
  selector:
    matchLabels:
      app: data-${1}
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

function printOrdererStorageYaml {
  # storage class for orderer config and data folders
  printStorageClass "orderer-data-class"

  # PV and PVC for orderer config and data
  for ord in "${ORDERERS[@]}"; do
    printDataPV ${ord} "orderer-data-class"
    if [ "${ORDERER_TYPE}" == "solo" ]; then
      # create only the first orderer for solo consensus
      break
    fi
  done
}

function printPeerStorageYaml {
  # storage class for orderer config and data folders
  printStorageClass "peer-data-class"

  # PV and PVC for peer config and data
  for p in "${PEERS[@]}"; do
    printDataPV ${p} "peer-data-class"
  done
}

function configPersistentData {
  for ord in "${ORDERERS[@]}"; do
    mkdir -p ${DATA_ROOT}/orderers/${ord}/data
    cp ${DATA_ROOT}/tool/genesis.block ${DATA_ROOT}/orderers/${ord}
  done

  for p in "${PEERS[@]}"; do
    mkdir -p ${DATA_ROOT}/peers/${p}/data
  done
}

function printNamespaceYaml {
  echo "
apiVersion: v1
kind: Namespace
metadata:
  name: netop1
  labels:
    use: hyperledger
"
}

function printOrdererYaml {
  ord_cnt=${#ORDERERS[@]}
  if [ "${ORDERER_TYPE}" == "solo" ]; then
    # create only the first orderer for solo consensus
    ord_cnt=1
  fi

  echo "
kind: Service
apiVersion: v1
metadata:
  name: orderer
  namespace: ${ORG}
  labels:
    app: orderer
spec:
  selector:
    app: orderer
  ports:
  - port: 7050
    name: server
  # headless service for orderer StatefulSet
  clusterIP: None
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: orderer
  namespace: ${ORG}
spec:
  selector:
    matchLabels:
      app: orderer
  serviceName: orderer
  replicas: ${ord_cnt}
  template:
    metadata:
      labels:
        app: orderer
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - name: orderer
        imagePullPolicy: Always
        image: hyperledger/fabric-orderer:1.4.3
        resources:
          requests:
            memory: \"1Gi\"
            cpu: 500m
        ports:
        - containerPort: 7050
          name: server
        command:
        - orderer
        env:
        - name: FABRIC_LOGGING_SPEC
          value: INFO
        - name: ORDERER_GENERAL_LISTENADDRESS
          value: 0.0.0.0
        - name: ORDERER_GENERAL_GENESISMETHOD
          value: file
        - name: ORDERER_FILELEDGER_LOCATION
          value: /var/hyperledger/orderer/store/data
        - name: ORDERER_GENERAL_GENESISFILE
          value: /var/hyperledger/orderer/store/genesis.block
        - name: ORDERER_GENERAL_LOCALMSPID
          value: ${ORDERER_MSP}
        - name: ORDERER_GENERAL_LOCALMSPDIR
          value: /var/hyperledger/orderer/store/crypto/msp
        - name: ORDERER_GENERAL_TLS_ENABLED
          value: \"true\"
        - name: ORDERER_GENERAL_TLS_PRIVATEKEY
          value: /var/hyperledger/orderer/store/crypto/tls/server.key
        - name: ORDERER_GENERAL_TLS_CERTIFICATE
          value: /var/hyperledger/orderer/store/crypto/tls/server.crt
        - name: ORDERER_GENERAL_TLS_ROOTCAS
          value: /var/hyperledger/orderer/store/crypto/tls/ca.crt
        - name: ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE
          value: /var/hyperledger/orderer/store/crypto/tls/server.crt
        - name: ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY
          value: /var/hyperledger/orderer/store/crypto/tls/server.key
        - name: ORDERER_GENERAL_CLUSTER_ROOTCAS
          value: /var/hyperledger/orderer/store/crypto/tls/server.crt
        - name: GODEBUG
          value: netdns=go
        volumeMounts:
        - mountPath: /var/hyperledger/orderer/store
          name: data
        workingDir: /opt/gopath/src/github.com/hyperledger/fabric/orderer
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: \"orderer-data-class\"
      resources:
        requests:
          storage: 500Mi"
}

function printPeerYaml {
  p_cnt=${#PEERS[@]}
  COUCHDB_USER=${COUCHDB_USER:-""}
  COUCHDB_PASSWD=${COUCHDB_PASSWD:-""}
  gossip_boot=""
  for p in "${PEERS[@]}"; do
    if [ -z "${gossip_boot}" ]; then
      gossip_boot="${p}.peer.${SVC_DOMAIN}:7051"
    else
      gossip_boot="${gossip_boot} ${p}.peer.${SVC_DOMAIN}:7051"
    fi
  done

  echo "
kind: Service
apiVersion: v1
metadata:
  name: peer
  namespace: ${ORG}
  labels:
    app: peer
spec:
  selector:
    app: peer
  ports:
    - name: external-listen-endpoint
      port: 7051
    - name: event-listen
      port: 7053
  clusterIP: None
---
kind: StatefulSet
apiVersion: apps/v1
metadata:
  name:	peer
  namespace: ${ORG}
spec:
  selector:
    matchLabels:
      app: peer
  serviceName: peer
  replicas: ${p_cnt}
  template:
    metadata:
      labels:
       app: peer
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - name: couchdb
        image: hyperledger/fabric-couchdb
        env:
        - name: COUCHDB_USER
          value: "${COUCHDB_USER}"
        - name: COUCHDB_PASSWORD
          value: "${COUCHDB_PASSWD}"
        ports:
         - containerPort: 5984
      - name: peer 
        image: hyperledger/fabric-peer
        resources:
          requests:
            memory: \"1Gi\"
            cpu: 500m
        env:
        - name: CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME
          value: "${COUCHDB_USER}"
        - name: CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD
          value: "${COUCHDB_PASSWD}"
        - name: CORE_LEDGER_STATE_STATEDATABASE
          value: CouchDB
        - name: CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS
          value: localhost:5984
        - name: CORE_PEER_LOCALMSPID
          value: ${ORG_MSP}
        - name: CORE_PEER_MSPCONFIGPATH
          value: /etc/hyperledger/peer/store/crypto/msp
        - name: CORE_PEER_LISTENADDRESS
          value: 0.0.0.0:7051
        - name: CORE_PEER_CHAINCODELISTENADDRESS
          value: 0.0.0.0:7052
        - name: CORE_VM_ENDPOINT
          value: unix:///host/var/run/docker.sock
        - name: CORE_VM_DOCKER_HOSTCONFIG_DNS
          value: ${DNS_IP}
        - name: FABRIC_LOGGING_SPEC
          value: INFO
        - name: CORE_PEER_TLS_ENABLED
          value: \"true\"
        - name: CORE_PEER_GOSSIP_USELEADERELECTION
          value: \"true\"
        - name: CORE_PEER_GOSSIP_ORGLEADER
          value: \"false\"
        - name: CORE_PEER_PROFILE_ENABLED
          value: \"true\"
        - name: CORE_PEER_TLS_CERT_FILE
          value: /etc/hyperledger/peer/store/crypto/tls/server.crt
        - name: CORE_PEER_TLS_KEY_FILE
          value: /etc/hyperledger/peer/store/crypto/tls/server.key
        - name: CORE_PEER_TLS_ROOTCERT_FILE
          value: /etc/hyperledger/peer/store/crypto/tls/ca.crt
        - name: CORE_PEER_FILESYSTEMPATH
          value: /etc/hyperledger/peer/store/data
        - name: GODEBUG
          value: netdns=go
        - name: CORE_PEER_GOSSIP_BOOTSTRAP
          value: \"${gossip_boot}\"
# following env depends on hostname, will be reset in startup command
        - name: CORE_PEER_ID
          value:
        - name: CORE_PEER_ADDRESS
          value:
        - name: CORE_PEER_CHAINCODEADDRESS
          value:
        - name: CORE_PEER_GOSSIP_EXTERNALENDPOINT
          value:
        workingDir: /opt/gopath/src/github.com/hyperledger/fabric/peer
        ports:
         - containerPort: 7051
         - containerPort: 7053
        command:
        - bash
        - -c
        - |
          CORE_PEER_ID=\$HOSTNAME.${FABRIC_ORG}
          CORE_PEER_ADDRESS=\$HOSTNAME.peer.${SVC_DOMAIN}:7051
          CORE_PEER_CHAINCODEADDRESS=\$HOSTNAME.peer.${SVC_DOMAIN}:7052
          CORE_PEER_GOSSIP_EXTERNALENDPOINT=\$HOSTNAME.peer.${SVC_DOMAIN}:7051
          env
          peer node start
        volumeMounts:
        - mountPath: /host/var/run
          name: docker-sock
        - mountPath: /etc/hyperledger/peer/store
          name: data
      volumes:
      - name: docker-sock
        hostPath:
          path: /var/run
          type: Directory
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: 
      - ReadWriteOnce
      storageClassName: \"peer-data-class\"
      resources:
        requests:
          storage: 500Mi"
}

function main {
  mkdir -p ${DATA_ROOT}/network/k8s
  getOrderers
  getPeers
  configPersistentData
  printNamespaceYaml > ${DATA_ROOT}/network/k8s/namespace.yaml
  printOrdererStorageYaml > ${DATA_ROOT}/network/k8s/orderer-pv.yaml
  printOrdererYaml > ${DATA_ROOT}/network/k8s/orderer.yaml
  printPeerStorageYaml > ${DATA_ROOT}/network/k8s/peer-pv.yaml
  printPeerYaml > ${DATA_ROOT}/network/k8s/peer.yaml

  # start network
  kubectl create -f ${DATA_ROOT}/network/k8s/namespace.yaml
  kubectl create -f ${DATA_ROOT}/network/k8s/orderer-pv.yaml
  kubectl create -f ${DATA_ROOT}/network/k8s/peer-pv.yaml
  kubectl create -f ${DATA_ROOT}/network/k8s/orderer.yaml
  kubectl create -f ${DATA_ROOT}/network/k8s/peer.yaml
}

main
