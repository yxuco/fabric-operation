#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# start or shutdown and test fabric network
# usage: network.sh <cmd> [-p <property file>] [-t <env type>] [-d]
# it uses a property file of the specified org as defined in ../config/org.env, e.g.
#   network.sh start -p netop1
# using config parameters specified in ../config/netop1.env
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

##############################################################################
# docker-compose functions
##############################################################################

# set list of couchdbs corresponding to peers
function getCouchdbs {
  COUCHDBS=()
  local seq=${PEER_MIN:-"0"}
  local max=${PEER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    COUCHDBS+=("couchdb-${seq}")
    seq=$((${seq}+1))
  done
}

# printOrdererService <seq>
# orderer data are persisted by named volume, e.g., orderer-0.netop1.com
# by default, it is set in orderer.yaml or env ORDERER_GENERAL_FILELEDGER_LOCATION=/var/hyperledger/production/orderer
# the named volume on localhost is under /var/lib/docker/volumes/docker_orderer-0.netop1.com
# On Mac, this volume exists in 'docker-desktop' VM, and can only be viewed after login to the VM via 'screen'
function printOrdererService {
  local ord=${ORDERERS[${1}]}
  local port=$((${1} * 10 + ${ORDERER_PORT}))
  echo "
  ${ord}.${FABRIC_ORG}:
    container_name: ${ord}.${FABRIC_ORG}
    image: hyperledger/fabric-orderer
    environment:
      - FABRIC_LOGGING_SPEC=INFO
      - ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
      - ORDERER_GENERAL_GENESISMETHOD=file
      - ORDERER_GENERAL_GENESISFILE=/var/hyperledger/orderer/orderer.genesis.block
      - ORDERER_GENERAL_LOCALMSPID=${ORDERER_MSP}
      - ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp
      # enabled TLS
      - ORDERER_GENERAL_TLS_ENABLED=true
      - ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_CLUSTER_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric
    command: orderer
    volumes:
        - ${DATA_ROOT}/tool/${ORDERER_TYPE}-genesis.block:/var/hyperledger/orderer/orderer.genesis.block
        - ${DATA_ROOT}/orderers/${ord}/crypto/msp/:/var/hyperledger/orderer/msp
        - ${DATA_ROOT}/orderers/${ord}/crypto/tls/:/var/hyperledger/orderer/tls
        - ${ord}.${FABRIC_ORG}:/var/hyperledger/production/orderer
    ports:
      - ${port}:7050
    networks:
      - ${ORG}"
  VOLUMES+=(${ord}.${FABRIC_ORG})
}

# printPeerService <seq>
# ledgers are persisted by named volume, e.g., peer-0.netop1.com
# by default, it is set in core.yaml or env CORE_PEER_FILESYSTEMPATH=/var/hyperledger/production
# the named volume on localhost is under /var/lib/docker/volumes/docker_peer-0.netop1.com
# On Mac, this volume exists in 'docker-desktop' VM, and can only be viewed after login to the VM via 'screen'
function printPeerService {
  local p=${PEERS[${1}]}
  local port=$((${1} * 10 + ${PEER_PORT}))

  local gossip_peer=${PEERS[0]}
  if [ "${1}" -eq "0" ]; then
    gossip_peer=${PEERS[1]}
  fi
  echo "
  ${p}.${FABRIC_ORG}:
    container_name: ${p}.${FABRIC_ORG}
    image: hyperledger/fabric-peer
    environment:
      - CORE_PEER_ID=${p}.${FABRIC_ORG}
      - CORE_PEER_ADDRESS=${p}.${FABRIC_ORG}:7051
      - CORE_PEER_LISTENADDRESS=0.0.0.0:7051
      - CORE_PEER_CHAINCODEADDRESS=${p}.${FABRIC_ORG}:7052
      - CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
      - CORE_PEER_GOSSIP_BOOTSTRAP=${gossip_peer}.${FABRIC_ORG}:7051
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=${p}.${FABRIC_ORG}:7051
      - CORE_PEER_LOCALMSPID=${ORG_MSP}
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      # the following setting starts chaincode containers on the same
      # bridge network as the peers
      # https://docs.docker.com/compose/networking/
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=docker_${ORG}
      - FABRIC_LOGGING_SPEC=INFO
      #- FABRIC_LOGGING_SPEC=DEBUG
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_GOSSIP_USELEADERELECTION=true
      - CORE_PEER_GOSSIP_ORGLEADER=false
      - CORE_PEER_PROFILE_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt"
  if [ "${STATE_DB}" == "couchdb" ]; then
    echo "
      - CORE_LEDGER_STATE_STATEDATABASE=CouchDB
      - CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS=${COUCHDBS[${1}]}:5984
      - CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME=${COUCHDB_USER}
      - CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD=${COUCHDB_PASSWD}"
  fi
  echo "
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    command: peer node start
    volumes:
        - /var/run/:/host/var/run/
        - ${DATA_ROOT}/peers/${p}/crypto/msp/:/etc/hyperledger/fabric/msp
        - ${DATA_ROOT}/peers/${p}/crypto/tls/:/etc/hyperledger/fabric/tls
        - ${p}.${FABRIC_ORG}:/var/hyperledger/production
    ports:
      - ${port}:7051
    networks:
      - ${ORG}"
  VOLUMES+=(${p}.${FABRIC_ORG})
  if [ "${STATE_DB}" == "couchdb" ]; then
    printCouchdbService ${1}
  fi
}

# printCouchdbService <seq>
# The API port COUCHDB_PORT can be used access the admin UI for development, e.g.,
# you can access the futon admin UI in a browser: http://localhost:5076/_utils
# No persistent volume is defined for CouchDB. No need to persist because 
# world state will be re-created at peer startup from the persisted ledger.
function printCouchdbService {
  local db=${COUCHDBS[${1}]}
  local port=$((${1} * 10 + ${COUCHDB_PORT}))
  echo "
  ${db}:
    container_name: ${db}
    image: hyperledger/fabric-couchdb
    environment:
      - COUCHDB_USER=${COUCHDB_USER}
      - COUCHDB_PASSWORD=${COUCHDB_PASSWD}
    # Comment/Uncomment the port mapping if you want to hide/expose the CouchDB service,
    # for example map it to utilize Fauxton User Interface in dev environments.
    ports:
      - ${port}:5984
    networks:
      - ${ORG}"
}

# cli container is used to create channel, instantiate chaincode, and check status, e.g.,
# docker exec -it cli bash
# peer channel list
# peer chaincode list -C mychannel --instantiated
function printCliService {
  local admin=${ADMIN_USER:-"Admin"}
  local ordorg="${FABRIC_ORG}"
  if [ "${ORDERER_MAX:-0}" -eq 0 ] && [ ! -z "${ORDERER_ORG}" ]; then
    ordorg="${ORDERER_ORG}"
  fi

  echo "
  cli:
    container_name: cli
    image: hyperledger/fabric-tools
    tty: true
    stdin_open: true
    environment:
      - GOPATH=/opt/gopath
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      #- FABRIC_LOGGING_SPEC=DEBUG
      - FABRIC_LOGGING_SPEC=INFO
      - ORG=${ORG}
      - SYS_CHANNEL=${SYS_CHANNEL}
      - TEST_CHANNEL=${TEST_CHANNEL}
      - ORDERER_TYPE=${ORDERER_TYPE}
      - CORE_PEER_ID=cli
      - CORE_PEER_ADDRESS=peer-0.${FABRIC_ORG}:7051
      - CORE_PEER_LOCALMSPID=${ORG_MSP}
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/cli/crypto/peer-0/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/cli/crypto/peer-0/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/cli/crypto/peer-0/tls/ca.crt
      - CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/cli/crypto/${admin}@${FABRIC_ORG}/msp
      - ORDERER_CA=/etc/hyperledger/cli/crypto/orderer-0/msp/tlscacerts/tlsca.${ordorg}-cert.pem
      - ORDERER_URL=orderer-0.${ordorg}:7050
      - FABRIC_ORG=${FABRIC_ORG}
    working_dir: /etc/hyperledger/cli
    command: /bin/bash
    volumes:
      - /var/run/:/host/var/run/
      - ${DATA_ROOT}/cli/:/etc/hyperledger/cli/
      - ${DATA_ROOT}/cli/chaincode/:/opt/gopath/src/github.com/chaincode:cached
    networks:
      - ${ORG}
    depends_on:"
  for p in "${PEERS[@]}"; do
    echo "      - ${p}.${FABRIC_ORG}"
  done
}

function printNetworkDockerYaml {
  echo "version: '2'

networks:
  ${ORG}:

services:"

  # place holder for named volumes used by the containers
  # Note: docker named volumes are created in, e.g., /var/lib/docker/volumes/docker_peer-0.netop1.com
  # On Mac, the named volumes are in the 'docker-desktop' VM. Use 'screen' to view the named volumes, i.e.,
  # screen ~/Library/Containers/com.docker.docker/Data/vms/0/tty
  # to exit from screen, Ctrl+A then Ctrl+D; to resume screen, screen -r
  VOLUMES=()

  # print orderer services
  getOrderers
  seq=${ORDERER_MIN:-"0"}
  max=${ORDERER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    printOrdererService ${seq}
    if [ "${ORDERER_TYPE}" == "solo" ]; then
      # create only the first orderer for solo consensus
      break
    fi
    seq=$((${seq}+1))
  done

  # print peer services
  getPeers
  if [ "${STATE_DB}" == "couchdb" ]; then
    getCouchdbs
  fi
  seq=${PEER_MIN:-"0"}
  max=${PEER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    printPeerService ${seq}
    seq=$((${seq}+1))
  done

  # print cli service for executing admin commands
  if [ "${PEER_MAX:-0}" -gt 0 ]; then
    printCliService
  fi

  # print named volumes
  if [ "${#VOLUMES[@]}" -gt "0" ]; then
    echo "
volumes:"
    for vol in "${VOLUMES[@]}"; do
      echo "  ${vol}:"
    done
  fi
}

##############################################################################
# Kubernetes functions
##############################################################################

# print k8s persistent volume for an orderer or peer
# even though volumeClaimTemplates can generate PVC automatically, 
# we define all PVCs here to guarantee that they match the corresponding PVs
# e.g., printDataPV "orderer-1" "orderer-data-class"
function printDataPV {
  local _store_size="${NODE_PV_SIZE}"
  if [ "${1}" == "cli" ]; then
    _store_size="${TOOL_PV_SIZE}"
  fi
  local _mode="ReadWriteOnce"
  local _folder="cli"
  if [ "${2}" == "${ORG}-orderer-data-class" ]; then
    _folder="orderers/${1}"
  elif [ "${2}" == "${ORG}-peer-data-class" ]; then
    _folder="peers/${1}"
  fi

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
  storageClassName: ${2}"

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
  storageClassName: ${2}
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

# printStorageClass <name>
# storage class for local host, or AWS EFS, Azure Files, of GCP Filestore
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
  name: ${1}
provisioner: ${_provision}
volumeBindingMode: WaitForFirstConsumer"

  if [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo "parameters:
  skuName: Standard_LRS"
  fi
}

function printOrdererStorageYaml {
  # storage class for orderer config and data folders
  printStorageClass "${ORG}-orderer-data-class"

  # PV and PVC for orderer config and data
  for ord in "${ORDERERS[@]}"; do
    printDataPV ${ord} "${ORG}-orderer-data-class"
    if [ "${ORDERER_TYPE}" == "solo" ]; then
      # create only the first orderer for solo consensus
      break
    fi
  done
}

# print PV and PVC for peer config and data
# printPeerStorageYaml [start-seq end-seq]
function printPeerStorageYaml {
  # default for all bootstrap peers
  local seq=${PEER_MIN:-"0"}
  local max=${PEER_MAX:-"0"}
  if [ -z "${1}" ]; then
    # storage class for orderer config and data folders
    printStorageClass "${ORG}-peer-data-class"
  else
    seq=${1}
    if [ -z "${2}" ]; then
      max=$((${seq}+1))
    else
      max=${2}
    fi
  fi
  until [ "${seq}" -ge "${max}" ]; do
    local p=("peer-${seq}")
    seq=$((${seq}+1))
    printDataPV ${p} "${ORG}-peer-data-class"
  done
}

function printCliStorageYaml {
  # storage class for cli data folders
  printStorageClass "${ORG}-cli-data-class"

  # PV and PVC for cli data
  printDataPV "cli" "${ORG}-cli-data-class"
}

function printOrdererYaml {
  local ord_cnt=${#ORDERERS[@]}
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
            memory: ${POD_MEM}
            cpu: ${POD_CPU}
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
      storageClassName: \"${ORG}-orderer-data-class\"
      resources:
        requests:
          storage: ${NODE_PV_SIZE}"
}

function printPeerYaml {
  local p_cnt=${#PEERS[@]}
  local gossip_boot=""
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
        resources:
          requests:
            memory: ${POD_MEM}
            cpu: ${POD_CPU}
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
            memory: ${POD_MEM}
            cpu: ${POD_CPU}
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
      storageClassName: \"${ORG}-peer-data-class\"
      resources:
        requests:
          storage: ${NODE_PV_SIZE}"
}

# printCliYaml <test-peer>
# e.g., printCliYaml peer-0
function printCliYaml {
  local admin=${ADMIN_USER:-"Admin"}
  local ord_ca="/etc/hyperledger/cli/store/crypto/orderer-0/msp/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem"
  local ord_url="orderer-0.orderer.${SVC_DOMAIN}:7050"
  if [ "${ORDERER_MAX:-0}" -eq 0 ] && [ ! -z "${ORDERER_ORG}" ]; then
    local o_org=${ORDERER_ORG%%.*}
    ord_ca="/etc/hyperledger/cli/store/crypto/orderer-0/msp/tlscacerts/tlsca.${ORDERER_ORG}-cert.pem"
    ord_url="orderer-0.orderer.${SVC_DOMAIN/${ORG}./${o_org}.}:7050"
  fi
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
    resources:
      requests:
        memory: ${POD_MEM}
        cpu: ${POD_CPU}
    command:
    - /bin/bash
    - -c
    - |
      mkdir -p /opt/gopath/src/github.com
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
      value: ${ord_ca}
    - name: ORDERER_TYPE
      value: ${ORDERER_TYPE}
    - name: ORDERER_URL
      value: ${ord_url}
    - name: ORG
      value: ${ORG}
    - name: FABRIC_ORG
      value: ${FABRIC_ORG}
    - name: SYS_CHANNEL
      value: ${SYS_CHANNEL}
    - name: TEST_CHANNEL
      value: ${TEST_CHANNEL}
    - name: SVC_DOMAIN
      value: ${SVC_DOMAIN}
    - name: ORDERER_MSP
      value: ${ORDERER_MSP}
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
      claimName: data-cli"
}

##############################################################################
# Network operations
##############################################################################

# scalePeer <replicas>
function scalePeer {
  if [ "${ENV_TYPE}" == "docker" ]; then
    echo "operation 'scale-peer' is not supported for docker-compose"
    return 0
  fi
  if [ -z "${1}" ]; then
    echo "replica count is not specified for scale-peer"
    printHelp
    return 1
  fi
  local rep=$(kubectl get statefulsets peer -n ${ORG} -o jsonpath='{.status.replicas}')
  if [ -z "${rep}" ]; then
    echo "Error: peer statefulset is not running"
    return 2
  fi
  echo "scale peer statefulset from ${rep} to ${1}"
  if [ "${rep}" -ge "${1}" ]; then
    echo "current replicas ${rep} is already greater than ${1}"
    return 0
  fi

  # check crypto data
  local seq=${rep}
  local max=${1}
  until [ ${seq} -ge ${max} ]; do
    local p=("peer-${seq}")
    seq=$((${seq}+1))
    if [ ! -d "${DATA_ROOT}/peers/${p}/crypto" ]; then
      echo "Error: crypto of ${p} does not exist"
      echo "create crypto using '../ca/ca-crypto.sh peer -s ${rep} -e ${1}'"
      return 2
    fi
    ${sumd} -p ${DATA_ROOT}/peers/${p}/data
  done

  max=$((${1}-1))
  echo "create persistent volume for peer-${rep} to peer-${max}"
  printPeerStorageYaml ${rep} ${1} | ${stee} ${DATA_ROOT}/network/k8s/peer-pv-${rep}.yaml > /dev/null
  kubectl create -f ${DATA_ROOT}/network/k8s/peer-pv-${rep}.yaml

  echo "scale peer statefulset to ${1}"
  local pvstat=$(kubectl get pv data-${ORG}-peer-${max} -o jsonpath='{.status.phase}')
  until [ "${pvstat}" == "Available" ]; do
    echo "wait 5s for persistent volume data-${ORG}-peer-${max} ..."
    sleep 5
    pvstat=$(kubectl get pv data-${ORG}-peer-${max} -o jsonpath='{.status.phase}')
  done
  kubectl scale statefulsets peer -n ${ORG} --replicas=${1}
}

# scaleOrderer <replicas>
function scaleOrderer {
  if [ "${ENV_TYPE}" == "docker" ]; then
    echo "operation 'scale-orderer' is not supported for docker-compose"
    return 0
  fi
  local rep=$(kubectl get statefulsets orderer -n ${ORG} -o jsonpath='{.status.replicas}')
  if [ -z "${rep}" ]; then
    echo "Error: orderer statefulset is not running"
    return 1
  fi

  if [ ! -z "${1}" ] && [ "${1}" -le "${rep}" ]; then
    echo "${rep} orderers already running"
    return 1
  fi
  
  local ord="orderer-${rep}"
  if [ ! -d "${DATA_ROOT}/orderers/${ord}/crypto" ]; then
    echo "Error: crypto of ${ord} does not exist"
    echo "create crypto using '../ca/ca-crypto.sh orderer -s ${rep}'"
    return 2
  fi
  ${sumd} -p ${DATA_ROOT}/orderers/${ord}/data
  ${sucp} ${DATA_ROOT}/tool/${ORDERER_TYPE}-genesis.block ${DATA_ROOT}/orderers/${ord}/genesis.block

  echo "create persistent volume for ${ord}"
  printDataPV ${ord} "${ORG}-orderer-data-class" | ${stee} ${DATA_ROOT}/network/k8s/orderer-pv-${rep}.yaml > /dev/null
  kubectl create -f ${DATA_ROOT}/network/k8s/orderer-pv-${rep}.yaml

  echo "add ${ord} to statefulset"
  local pvstat=$(kubectl get pv data-${ORG}-${ord} -o jsonpath='{.status.phase}')
  until [ "${pvstat}" == "Available" ]; do
    echo "wait 5s for persistent volume data-${ORG}-${ord} ..."
    sleep 5
    pvstat=$(kubectl get pv data-${ORG}-${ord} -o jsonpath='{.status.phase}')
  done
  rep=$((${rep}+1))
  kubectl scale statefulsets orderer -n ${ORG} --replicas=${rep}
}

function configPersistentData {
  for ord in "${ORDERERS[@]}"; do
    ${sumd} -p ${DATA_ROOT}/orderers/${ord}/data
    ${sucp} ${DATA_ROOT}/tool/${ORDERER_TYPE}-genesis.block ${DATA_ROOT}/orderers/${ord}/genesis.block
  done

  for p in "${PEERS[@]}"; do
    ${sumd} -p ${DATA_ROOT}/peers/${p}/data
  done
}

function startNetwork {
  # prepare folder for chaincode testing
  ${sumd} -p ${DATA_ROOT}/cli/chaincode

  if [ "${ENV_TYPE}" == "docker" ]; then
    ORDERER_PORT=${ORDERER_PORT:-"7050"}
    PEER_PORT=${PEER_PORT:-"7051"}
    COUCHDB_PORT=${COUCHDB_PORT:-"7056"}

    mkdir -p ${DATA_ROOT}/network/docker
    printNetworkDockerYaml > ${DATA_ROOT}/network/docker/docker-compose.yaml
    docker-compose -f ${DATA_ROOT}/network/docker/docker-compose.yaml up -d
  else
    ${sumd} -p ${DATA_ROOT}/network/k8s
    getOrderers
    getPeers
    configPersistentData
    if [ "${ORDERER_MAX:-0}" -gt 0 ]; then
      printOrdererStorageYaml | ${stee} ${DATA_ROOT}/network/k8s/orderer-pv.yaml > /dev/null
      printOrdererYaml | ${stee} ${DATA_ROOT}/network/k8s/orderer.yaml > /dev/null
    fi
    if [ "${PEER_MAX:-0}" -gt 0 ]; then
      printPeerStorageYaml | ${stee} ${DATA_ROOT}/network/k8s/peer-pv.yaml > /dev/null
      printPeerYaml | ${stee} ${DATA_ROOT}/network/k8s/peer.yaml > /dev/null
      printCliStorageYaml | ${stee} ${DATA_ROOT}/network/k8s/cli-pv.yaml > /dev/null
      printCliYaml peer-0 | ${stee} ${DATA_ROOT}/network/k8s/cli.yaml > /dev/null
    fi

    # copy orderer cert for CLI if available
    if [ "${ORDERER_MAX:-0}" -eq 0 ] && [ ! -z "${ORDERER_ORG}" ]; then
      local ordcert=${DATA_ROOT}/../${ORDERER_ORG}/cli/crypto/orderer-0
      if [ -d "${ordcert}" ]; then
        echo "copy orderer TLS cert from ${ordcert}"
        ${sucp} -R ${ordcert} ${DATA_ROOT}/cli/crypto
      fi
    fi

    # start network
    if [ "${ORDERER_MAX:-0}" -gt 0 ]; then
      kubectl create -f ${DATA_ROOT}/network/k8s/orderer-pv.yaml
      kubectl create -f ${DATA_ROOT}/network/k8s/orderer.yaml
    fi
    if [ "${PEER_MAX:-0}" -gt 0 ]; then
      kubectl create -f ${DATA_ROOT}/network/k8s/peer-pv.yaml
      kubectl create -f ${DATA_ROOT}/network/k8s/cli-pv.yaml
      kubectl create -f ${DATA_ROOT}/network/k8s/peer.yaml
      kubectl create -f ${DATA_ROOT}/network/k8s/cli.yaml
    fi
  fi

  # copy network-util script to artifacts
  if [ -f "${SCRIPT_DIR}/network-util.sh" ]; then
    echo "copy network-util script ${SCRIPT_DIR}/network-util.sh"
    ${sucp} ${SCRIPT_DIR}/network-util.sh ${DATA_ROOT}/cli
  fi
}

function shutdownNetwork {
  if [ "${ENV_TYPE}" == "docker" ]; then
    # shutdown fabric network, and cleanup persisent volumes
    local vols=""
    if [ "${CLEANUP}" == "true" ]; then
      # set param to for deleting named volumes
      vols="--volumes"
    fi
    docker-compose -f ${DATA_ROOT}/network/docker/docker-compose.yaml down --remove-orphans ${vols}

    # cleanup chaincode containers and images
    docker rm $(docker ps -a | grep dev-peer | awk '{print $1}')
    docker rmi $(docker images | grep dev-peer | awk '{print $3}')
  else
    echo "stop cli pod ..."
    kubectl delete -f ${DATA_ROOT}/network/k8s/cli.yaml
    kubectl delete -f ${DATA_ROOT}/network/k8s/cli-pv.yaml

    echo "stop fabric network ..."
    kubectl delete -f ${DATA_ROOT}/network/k8s/peer.yaml
    for f in ${DATA_ROOT}/network/k8s/peer-pv*.yaml; do
      kubectl delete -f ${f}
    done
    kubectl delete -f ${DATA_ROOT}/network/k8s/orderer.yaml
    for f in ${DATA_ROOT}/network/k8s/orderer-pv*.yaml; do
      kubectl delete -f ${f}
    done

    if [ "${CLEANUP}" == "true" ]; then
      echo "clean up orderer ledger files ..."
      for d in "${DATA_ROOT}/orderers/*/data"; do
        ${surm} -R ${d}/*
      done

      echo "clean up peer ledger files ..."
      for d in "${DATA_ROOT}/peers/*/data"; do
        ${surm} -R ${d}/*
      done
    fi
  fi
}

function execUtil {
  local _cmd="network-util.sh $@"
  if [ "${ENV_TYPE}" == "docker" ]; then  
    echo "use docker-compose - ${_cmd}"
    docker exec -it cli bash -c "./${_cmd}"
  else
    echo "use k8s - ${_cmd}"
    kubectl exec -it cli -n ${ORG} -- bash -c "./${_cmd}"
  fi
}

# copy chaincode from scripts folder to $DATA_ROOT
# copyChaincode <cc_src>
function copyChaincode {
  local target=${DATA_ROOT}/cli/chaincode/${1}
  if [ -d "${target}" ]; then
    echo "refresh chaincode in ${target}"
    ${surm} -R ${target}/*
  else
    ${sumd} -p ${target}
  fi

  # copy test chaincode
  local chaincode=$(dirname "${SCRIPT_DIR}")/chaincode/${1}
  if [ -d "${chaincode}" ]; then
    echo "copy chaincode from ${chaincode}"
    ${sucp} -R ${chaincode}/* ${target}
  else
    echo "cannot find test chaincode ${chaincode}"
    return 1
  fi
}

# copyChannelTx <channel>
function copyChannelTx {
  if [ -f "${DATA_ROOT}/tool/${1}.tx" ]; then
    echo "copy channel tx from ${DATA_ROOT}/tool/${1}.tx"
    ${sucp} ${DATA_ROOT}/tool/${1}.tx ${DATA_ROOT}/cli
    ${sucp} ${DATA_ROOT}/tool/${1}-anchors.tx ${DATA_ROOT}/cli
  else
    echo "cannot find channel tx file: tool/${1}.tx. It must be created first by using msp-util.sh."
    return 1
  fi
}

function smokeTest {
  # copy test chaincode
  copyChaincode "chaincode_example02"

  # copy channel tx
  copyChannelTx ${TEST_CHANNEL}

  # run smoke test
  execUtil "test"
}

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  network.sh <cmd> [-p <property file>] [-t <env type>] [-d]"
  echo "    <cmd> - one of the following commands:"
  echo "      - 'start' - start orderers and peers of the fabric network, arguments: [-p <prop-file>] [-t <env-type>]"
  echo "      - 'shutdown' - shutdown orderers and peers of the fabric network, arguments: [-p <prop-file>] [-t <env-type>] [-d]"
  echo "      - 'test' - run smoke test"
  echo "      - 'scale-peer' - scale up peer nodes with argument '-r <replicas>'"
  echo "      - 'scale-orderer' - scale up orderer nodes (RAFT consenter only one at a time)"
  echo "      - 'create-channel' - create a channel using peer-0, with argument '-c <channel>'"
  echo "      - 'join-channel' - join a peer to a channel with arguments: -n <peer> -c <channel> [-a]"
  echo "        e.g., network.sh join-channel -n peer-0 -c mychannel -a"
  echo "      - 'package-chaincode' - package chaincode on a peer with arguments: -n <peer> -f <folder> -s <name> [-v <version>] [-g <lang>] [-e <policy>]"
  echo "        e.g., network.sh package-chaincode -n peer-0 -f chaincode_example02/go -s mycc -v 1.0 -g golang -e \"OR ('netop1MSP.admin')\""
  echo "      - 'sign-chaincode' - sign chaincode package on a peer with arguments: -n <peer> -f <cds-file>"
  echo "        e.g., network.sh sign-chaincode -n peer-0 -f mycc_1.0.cds"
  echo "      - 'install-chaincode' - install chaincode on a peer with arguments: -n <peer> -f <cds-file>"
  echo "        e.g., network.sh install-chaincode -n peer-0 -f mycc_1.0.cds"
  echo "      - 'instantiate-chaincode' - instantiate chaincode on a peer, with arguments: -n <peer> -c <channel> -s <name> [-v <version>] [-m <args>] [-e <policy>] [-g <lang>]"
  echo "        e.g., network.sh instantiate-chaincode -n peer-0 -c mychannel -s mycc -v 1.0 -m '{\"Args\":[\"init\",\"a\",\"100\",\"b\",\"200\"]}'"
  echo "      - 'upgrade-chaincode' - upgrade chaincode on a peer, with arguments: -n <peer> -c <channel> -s <name> -v <version> [-m <args>] [-e <policy>] [-g <lang>]"
  echo "        e.g., network.sh upgrade-chaincode -n peer-0 -c mychannel -s mycc -v 2.0 -m '{\"Args\":[\"init\",\"a\",\"100\",\"b\",\"200\"]}'"
  echo "      - 'query-chaincode' - query chaincode from a peer, with arguments: -n <peer> -c <channel> -s <name> -m <args>"
  echo "        e.g., network.sh query-chaincode -n peer-0 -c mychannel -s mycc -m '{\"Args\":[\"query\",\"a\"]}'"
  echo "      - 'invoke-chaincode' - invoke chaincode from a peer, with arguments: -n <peer> -c <channel> -s <name> -m <args>"
  echo "        e.g., network.sh invoke-chaincode -n peer-0 -c mychannel -s mycc -m '{\"Args\":[\"invoke\",\"a\",\"b\",\"10\"]}'"
  echo "      - 'add-org-tx' - generate update tx for add new msp to a channel, with arguments: -o <msp> -c <channel>"
  echo "        e.g., network.sh add-org-tx -o peerorg1MSP -c mychannel"
  echo "      - 'add-orderer-tx' - generate update tx for add new orderers to a channel (default system-channel) for RAFT consensus, with argument: -f <consenter-file> [-c <channel>]"
  echo "        e.g., network.sh add-orderer-tx -f ordererConfig-3.json"
  echo "      - 'sign-transaction' - sign a config update transaction file in the CLI working directory, with argument = -f <tx-file>"
  echo "        e.g., network.sh sign-transaction -f \"mychannel-peerorg1MSP.pb\""
  echo "      - 'update-channel' - send transaction to update a channel, with arguments ('-a' means orderer user): -f <tx-file> -c <channel> [-a]"
  echo "        e.g., network.sh update-channel -f \"mychannel-peerorg1MSP.pb\" -c mychannel"
  echo "    -p <property file> - the .env file in config folder that defines network properties, e.g., netop1 (default)"
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', or 'az'"
  echo "    -d - delete ledger data when shutdown network"
  echo "    -r <replicas> - new peer node replica count for scale-peer"
  echo "    -n <peer> - peer ID for channel/chaincode commands"
  echo "    -c <channel> - channel ID for channel/chaincode commands"
  echo "    -a - update anchor for join-channel, or copy new chaincode for install-chaincode"
  echo "    -f <cc folder> - chaincode folder name, or config transaction file"
  echo "    -s <cc name> - chaincode name"
  echo "    -v <cc version> - chaincode version"
  echo "    -g <cc language> - chaincode language, default 'golang'"
  echo "    -m <args> - args for chaincode commands"
  echo "    -e <policy> - endorsement policy for instantiate/upgrade chaincode, e.g., \"OR ('Org1MSP.peer')\""
  echo "    -o <org msp> - org msp to be added to a channel"
  echo "  network.sh -h (print this message)"
}

ORG_ENV="netop1"

CMD=${1}
shift
while getopts "h?p:t:r:n:c:f:s:v:g:m:e:o:ad" opt; do
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
  d)
    CLEANUP="true"
    ;;
  r)
    REPLICA=$OPTARG
    ;;
  n)
    PEER_ID=$OPTARG
    ;;
  c)
    CHANNEL_ID=$OPTARG
    ;;
  f)
    CC_SRC=$OPTARG
    ;;
  s)
    CC_NAME=$OPTARG
    ;;
  v)
    CC_VERSION=$OPTARG
    ;;
  g)
    CC_LANG=$OPTARG
    ;;
  m)
    PARAM=$OPTARG
    ;;
  e)
    POLICY=$OPTARG
    ;;
  o)
    MSP=$OPTARG
    ;;
  a)
    NEW="true"
    ;;
  esac
done

source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORG_ENV} ${ENV_TYPE}
COUCHDB_USER=${COUCHDB_USER:-""}
COUCHDB_PASSWD=${COUCHDB_PASSWD:-""}
POD_CPU=${POD_CPU:-"500m"}
POD_MEM=${POD_MEM:-"1Gi"}

case "${CMD}" in
start)
  echo "start fabric network: ${ORG_ENV} ${ENV_TYPE}"
  startNetwork
  ;;
shutdown)
  echo "shutdown fabric network: ${ORG_ENV} ${ENV_TYPE}"
  shutdownNetwork
  ;;
test)
  echo "smoke test fabric network: ${ORG_ENV} ${ENV_TYPE}"
  smokeTest
  ;;
scale-peer)
  echo "scale up peer nodes: ${REPLICA}"
  scalePeer ${REPLICA}
  ;;
scale-orderer)
  echo "scale up orderer nodes: ${REPLICA}"
  scaleOrderer ${REPLICA}
  ;;
create-channel)
  echo "create channel: ${CHANNEL_ID}"
  if [ -z "${CHANNEL_ID}" ]; then
    echo "Invalid request: channel ID is not specified"
    printHelp
    exit 1
  fi
  if [ -f "${DATA_ROOT}/tool/${CHANNEL_ID}.tx" ]; then
    ${sucp} ${DATA_ROOT}/tool/${CHANNEL_ID}.tx ${DATA_ROOT}/cli
  fi
  execUtil ${CMD} ${CHANNEL_ID}
  ;;
join-channel)
  echo "join channel: ${PEER_ID} ${CHANNEL_ID} ${NEW}"
  if [ -z "${PEER_ID}" ] || [ -z "${CHANNEL_ID}" ]; then
    echo "Invalid request: peer and channel must be specified"
    printHelp
    exit 1
  fi
  copyChannelTx ${CHANNEL_ID}
  if [ -z "${NEW}" ]; then
    execUtil ${CMD} ${PEER_ID} ${CHANNEL_ID}
  else
    execUtil ${CMD} ${PEER_ID} ${CHANNEL_ID} "anchor"
  fi
  ;;
package-chaincode)
  echo "package chaincode: ${PEER_ID} ${CC_SRC} ${CC_NAME} ${CC_VERSION} ${CC_LANG} ${POLICY}"
  if [ -z "${PEER_ID}" ] || [ -z "${CC_SRC}" ] || [ -z "${CC_NAME}" ]; then
    echo "Invalid request: peer, chaincode folder and chaincode name must be specified"
    printHelp
    exit 1
  fi
  copyChaincode ${CC_SRC}
  execUtil "${CMD} ${PEER_ID} ${CC_SRC} ${CC_NAME} \"${CC_VERSION}\" \"${CC_LANG}\" \"${POLICY}\""
  ;;
sign-chaincode)
  echo "sign chaincode: ${PEER_ID} ${CC_SRC}"
  if [ -z "${PEER_ID}" ] || [ -z "${CC_SRC}" ]; then
    echo "Invalid request: peer, chaincode package file name must be specified"
    printHelp
    exit 1
  fi
  execUtil ${CMD} ${PEER_ID} ${CC_SRC}
  ;;
install-chaincode)
  echo "install chaincode: ${PEER_ID} ${CC_SRC}"
  if [ -z "${PEER_ID}" ] || [ -z "${CC_SRC}" ]; then
    echo "Invalid request: peer, chaincode package file name must be specified"
    printHelp
    exit 1
  fi
  if [ -f "${DATA_ROOT}/tool/${CC_SRC}" ]; then
    ${sumv} ${DATA_ROOT}/tool/${CC_SRC} ${DATA_ROOT}/cli
  fi
  execUtil ${CMD} ${PEER_ID} ${CC_SRC}
  ;;
instantiate-chaincode)
  echo "instantiate chaincode: ${PEER_ID} ${CHANNEL_ID} ${CC_NAME} ${CC_VERSION} ${PARAM} ${POLICY} ${CC_LANG}"
  if [ -z "${PEER_ID}" ] || [ -z "${CHANNEL_ID}" ] || [ -z "${CC_NAME}" ]; then
    echo "Invalid request: peer, channel and chaincode name must be specified"
    printHelp
    exit 1
  fi
  execUtil "${CMD} ${PEER_ID} ${CHANNEL_ID} ${CC_NAME} \"${CC_VERSION}\" '${PARAM}' \"${POLICY}\" \"${CC_LANG}\""
  ;;
upgrade-chaincode)
  echo "upgrade chaincode: ${PEER_ID} ${CHANNEL_ID} ${CC_NAME} ${CC_VERSION} ${PARAM} ${POLICY} ${CC_LANG}"
  if [ -z "${PEER_ID}" ] || [ -z "${CHANNEL_ID}" ] || [ -z "${CC_NAME}" ] || [ -z "${CC_VERSION}" ]; then
    echo "Invalid request: peer, channel, chaincode name and version must be specified"
    printHelp
    exit 1
  fi
  execUtil "${CMD} ${PEER_ID} ${CHANNEL_ID} ${CC_NAME} \"${CC_VERSION}\" '${PARAM}' \"${POLICY}\" \"${CC_LANG}\""
  ;;
query-chaincode)
  echo "query chaincode: ${PEER_ID} ${CHANNEL_ID} ${CC_NAME} ${PARAM}"
  if [ -z "${PEER_ID}" ] || [ -z "${CHANNEL_ID}" ] || [ -z "${CC_NAME}" ] || [ -z "${PARAM}" ]; then
    echo "Invalid request: peer, channel, chaincode name and query params must be specified"
    printHelp
    exit 1
  fi
  execUtil "${CMD} ${PEER_ID} ${CHANNEL_ID} ${CC_NAME} '${PARAM}'"
  ;;
invoke-chaincode)
  echo "invoke chaincode: ${PEER_ID} ${CHANNEL_ID} ${CC_NAME} ${PARAM}"
  if [ -z "${PEER_ID}" ] || [ -z "${CHANNEL_ID}" ] || [ -z "${CC_NAME}" ] || [ -z "${PARAM}" ]; then
    echo "Invalid request: peer, channel, chaincode name and invoke params must be specified"
    printHelp
    exit 1
  fi
  execUtil "${CMD} ${PEER_ID} ${CHANNEL_ID} ${CC_NAME} '${PARAM}'"
  ;;
add-org-tx)
  echo "create channel update to add org: ${MSP} ${CHANNEL_ID}"
  if [ -z "${MSP}" ] || [ -z "${CHANNEL_ID}" ]; then
    echo "Invalid request: org MSP and channel must be specified"
    printHelp
    exit 1
  fi
  execUtil "${CMD} ${MSP} ${CHANNEL_ID}"
  ;;
add-orderer-tx)
  echo "create channel update to add orderer: ${CC_SRC} ${CHANNEL_ID}"
  if [ -z "${CC_SRC}" ]; then
    echo "Invalid request: new consenter config file must be specified"
    printHelp
    exit 1
  fi
  if [ -f "${DATA_ROOT}/tool/${CC_SRC}" ]; then
    ${sucp} ${DATA_ROOT}/tool/${CC_SRC} ${DATA_ROOT}/cli
  fi
  execUtil "${CMD} ${CC_SRC} ${CHANNEL_ID}"
  ;;
sign-transaction)
  if [ -z "${CC_SRC}" ]; then
    echo "Invalid request: transaction file ${CC_SRC} not specified"
    printUsage
    exit 1
  fi
  echo "sign transaction ${CC_SRC}"
  execUtil "${CMD} ${CC_SRC}"
  ;;
update-channel)
  if [ -z "${CC_SRC}" ]; then
    echo "Invalid request: transaction file ${CC_SRC} not specified"
    printUsage
    exit 1
  fi
  if [ -z "${CHANNEL_ID}" ]; then
    echo "Invalid request: channel is not specified"
    printUsage
    exit 2
  fi
  echo "send transaction ${CC_SRC} to update channel ${CHANNEL_ID}, is-orderer: ${NEW}"
  execUtil "${CMD} ${CC_SRC} ${CHANNEL_ID} ${NEW}"
  ;;
*)
  printHelp
  exit 1
esac
