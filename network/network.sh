#!/bin/bash
# start or shutdown and test fabric network
# usage: network.sh <cmd> [-p <property file>] [-t <env type>] [-d]
# it uses a property file of the specified org as defined in ../config/org.env, e.g.
#   network.sh start -p netop1
# using config parameters specified in ../config/netop1.env
# the env_type can be k8s or aws/az/gke to use local host or a cloud file system, i.e. efs/azf/gfs, default k8s for local persistence

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
        - ${DATA_ROOT}/tool/genesis.block:/var/hyperledger/orderer/orderer.genesis.block
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
      - CORE_PEER_ADDRESS=${PEERS[0]}.${FABRIC_ORG}:7051
      - CORE_PEER_LOCALMSPID=${ORG_MSP}
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/cli/crypto/${PEERS[0]}/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/cli/crypto/${PEERS[0]}/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/cli/crypto/${PEERS[0]}/tls/ca.crt
      - CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/cli/crypto/${admin}@${FABRIC_ORG}/msp
      - ORDERER_CA=/etc/hyperledger/cli/crypto/${ORDERERS[0]}/msp/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem
      - ORDERER_URL=${ORDERERS[0]}.${FABRIC_ORG}:7050
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
  printCliService

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
  local _store_size="500Mi"
  if [ "${1}" == "cli" ]; then
    _store_size="100Mi"
  fi
  local _mode="ReadWriteOnce"
  local _folder="cli"
  if [ "${2}" == "orderer-data-class" ]; then
    _folder="orderers/${1}"
  elif [ "${2}" == "peer-data-class" ]; then
    _folder="peers/${1}"
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
    server: ${GKE_STORE_IP}
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

function printCliStorageYaml {
  # storage class for cli data folders
  printStorageClass "cli-data-class"

  # PV and PVC for cli data
  printDataPV "cli" "cli-data-class"
}

function configPersistentData {
  for ord in "${ORDERERS[@]}"; do
    ${sumd} -p ${DATA_ROOT}/orderers/${ord}/data
    ${sucp} ${DATA_ROOT}/tool/genesis.block ${DATA_ROOT}/orderers/${ord}
  done

  for p in "${PEERS[@]}"; do
    ${sumd} -p ${DATA_ROOT}/peers/${p}/data
  done
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
      storageClassName: \"orderer-data-class\"
      resources:
        requests:
          storage: 500Mi"
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
      storageClassName: \"peer-data-class\"
      resources:
        requests:
          storage: 500Mi"
}

# printCliYaml <test-peer>
# e.g., printCliYaml peer-0
function printCliYaml {
  local admin=${ADMIN_USER:-"Admin"}
  local test_ord=${ORDERERS[0]}
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
      value: /etc/hyperledger/cli/store/crypto/${test_ord}/msp/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem
    - name: ORDERER_TYPE
      value: ${ORDERER_TYPE}
    - name: ORDERER_URL
      value: ${test_ord}.orderer.${SVC_DOMAIN}:7050
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
      claimName: data-cli"
}

##############################################################################
# Network operations
##############################################################################

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
    printOrdererStorageYaml | ${stee} ${DATA_ROOT}/network/k8s/orderer-pv.yaml > /dev/null
    printOrdererYaml | ${stee} ${DATA_ROOT}/network/k8s/orderer.yaml > /dev/null
    printPeerStorageYaml | ${stee} ${DATA_ROOT}/network/k8s/peer-pv.yaml > /dev/null
    printPeerYaml | ${stee} ${DATA_ROOT}/network/k8s/peer.yaml > /dev/null
    printCliStorageYaml | ${stee} ${DATA_ROOT}/network/k8s/cli-pv.yaml > /dev/null
    printCliYaml peer-0 | ${stee} ${DATA_ROOT}/network/k8s/cli.yaml > /dev/null

    # start network
    kubectl create -f ${DATA_ROOT}/network/k8s/orderer-pv.yaml
    kubectl create -f ${DATA_ROOT}/network/k8s/peer-pv.yaml
    kubectl create -f ${DATA_ROOT}/network/k8s/cli-pv.yaml
    kubectl create -f ${DATA_ROOT}/network/k8s/orderer.yaml
    kubectl create -f ${DATA_ROOT}/network/k8s/peer.yaml
    kubectl create -f ${DATA_ROOT}/network/k8s/cli.yaml
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
    kubectl delete -f ${DATA_ROOT}/network/k8s/peer-pv.yaml
    kubectl delete -f ${DATA_ROOT}/network/k8s/orderer.yaml
    kubectl delete -f ${DATA_ROOT}/network/k8s/orderer-pv.yaml

    if [ "${CLEANUP}" == "true" ]; then
      echo "clean up orderer ledger files ..."
      getOrderers
      for ord in "${ORDERERS[@]}"; do
        ${surm} -R ${DATA_ROOT}/orderers/${ord}/data/*
      done

      echo "clean up peer ledger files ..."
      getPeers
      for p in "${PEERS[@]}"; do
        ${surm} -R ${DATA_ROOT}/peers/${p}/data/*
      done
    fi
  fi
}

function smokeTest {
  # copy test chaincode
  local chaincode=$(dirname "${SCRIPT_DIR}")/chaincode
  if [ -d "${chaincode}" ]; then
    echo "copy chaincode from ${chaincode}"
    ${sucp} -R ${chaincode}/* ${DATA_ROOT}/cli/chaincode
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

  # run smoke test
  if [ "${ENV_TYPE}" == "docker" ]; then
    docker exec -it cli bash -c './test-sample.sh'
  else
    kubectl exec -it cli -- bash -c 'cp -R ./chaincode /opt/gopath/src/github.com && ./test-sample.sh'
  fi
}

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  network.sh <cmd> [-p <property file>] [-t <env type>] [-d]"
  echo "    <cmd> - one of 'start', 'shutdown', or 'test'"
  echo "      - 'start' - start orderers and peers of the fabric network"
  echo "      - 'shutdown' - shutdown orderers and peers of the fabric network"
  echo "      - 'test' - run smoke test"
  echo "    -p <property file> - the .env file in config folder that defines network properties, e.g., netop1 (default)"
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', or 'az'"
  echo "    -d - delete ledger data when shutdown network"
  echo "  network.sh -h (print this message)"
}

ORG_ENV="netop1"
ENV_TYPE="k8s"

CMD=${1}
shift
while getopts "h?p:t:d" opt; do
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
  esac
done

source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORG_ENV} ${ENV_TYPE}
ORG_MSP="${ORG}MSP"
ORDERER_MSP=${ORDERER_MSP:-"${ORG}OrdererMSP"}
SYS_CHANNEL=${SYS_CHANNEL:-"${ORG}-channel"}
TEST_CHANNEL=${TEST_CHANNEL:-"mychannel"}
ORDERER_TYPE=${ORDERER_TYPE:-"solo"}
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
*)
  printHelp
  exit 1
esac
