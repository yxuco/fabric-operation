#!/bin/bash
# create and start fabric network for Mac docker-desktop Kubernetes
# usage: start-k8s.sh <org_name>
# it uses config parameters of the specified org as defined in ../config/org.env, e.g.
#   start-k8s.sh netop1
# using config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source ${SCRIPT_DIR}/setup.sh ${1:-"netop1"} k8s

MSP_DIR=$(dirname "${SCRIPT_DIR}")/${FABRIC_ORG}
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

# print k8s persistent volume for an orderer
# even though volumeClaimTemplates can generate PVC automatically, 
# we define all PVCs here to guarantee that they match the corresponding PVs
# e.g., printOrdererPV orderer-1
function printOrdererPV {
  echo "---
kind: PersistentVolume
apiVersion: v1
# create one PV for each orderer instance
metadata:
  name: data-${1}
  labels:
    node: ${1}
    org: ${ORG}
spec:
  capacity:
    storage: 500Mi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: orderer-data-class
  hostPath:
    path: ${MSP_DIR}/k8s/data/${1}
    type: DirectoryOrCreate
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: data-${1}
  namespace: ${ORG}
spec:
  storageClassName: orderer-data-class
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
  selector:
    matchLabels:
      node: ${1}
      org: ${ORG}
---
kind: PersistentVolume
apiVersion: v1
# create one PV for each orderer instance
metadata:
  name: config-${1}
  labels:
    node: ${1}
    org: ${ORG}
spec:
  capacity:
    storage: 100Mi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: orderer-config-class
  hostPath:
    path: ${MSP_DIR}/orderers/${1}.${FABRIC_ORG}
    type: Directory
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: config-${1}
  namespace: ${ORG}
spec:
  storageClassName: orderer-config-class
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
  selector:
    matchLabels:
      node: ${1}
      org: ${ORG}"
}

function printOrdererStorageYaml {
  # storage class for orderer config and data folders
  echo "
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: orderer-data-class
# use localhost data folder
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: orderer-config-class
# use localhost config folder
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
"

  # PV and PVC for orderer config and data
  for ord in "${ORDERERS[@]}"; do
    printOrdererPV ${ord}
    if [ "${ORDERER_TYPE}" == "solo" ]; then
      # create only the first orderer for solo consensus
      break
    fi
  done

  # PV and PVC for orderer scripts
  echo "---
kind: PersistentVolume
apiVersion: v1
# scripts for all orderers
metadata:
  name: scripts-orderer
  labels:
    app: orderer
    org: ${ORG}
spec:
  capacity:
    storage: 100Mi
  volumeMode: Filesystem
  accessModes:
  - ReadOnlyMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: ${MSP_DIR}/k8s/scripts
    type: Directory
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: scripts-orderer
  namespace: ${ORG}
spec:
  storageClassName: manual
  accessModes:
    - ReadOnlyMany
  resources:
    requests:
      storage: 100Mi
  selector:
    matchLabels:
      app: orderer
      org: ${ORG}"
}

# print k8s persistent volume for a peer
# even though volumeClaimTemplates can generate PVC automatically, 
# we define all PVCs here to guarantee that they match the corresponding PVs
# e.g., printPeerPV peer-1
function printPeerPV {
  echo "---
kind: PersistentVolume
apiVersion: v1
# create one PV for each peer instance
metadata:
  name: config-${1}
  labels:
    node: ${1}
    org: ${ORG}
spec:
  capacity:
    storage: 100Mi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: peer-config-class
  hostPath:
    path: ${MSP_DIR}/peers/${1}.${FABRIC_ORG}
    type: Directory
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: config-${1}
  namespace: ${ORG}
spec:
  storageClassName: peer-config-class
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
  selector:
    matchLabels:
      node: ${1}
      org: ${ORG}"
}

function printPeerStorageYaml {
  # storage class for orderer config and data folders
  echo "
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: peer-config-class
# use localhost config folder
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
"

  # PV and PVC for peer config and data
  for p in "${PEERS[@]}"; do
    printPeerPV ${p}
  done
}

function configPersistentData {
  for ord in "${ORDERERS[@]}"; do
    mkdir -p ${MSP_DIR}/k8s/data/${ord}
  done
  mkdir -p ${MSP_DIR}/k8s/scripts
  cp ${MSP_DIR}/artifacts/genesis.block ${MSP_DIR}/k8s/scripts
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
#        - name: FABRIC_CFG_PATH
#          value: /var/hyperledger/orderer/config
        - name: FABRIC_LOGGING_SPEC
          value: INFO
        - name: ORDERER_GENERAL_LISTENADDRESS
          value: 0.0.0.0
        - name: ORDERER_GENERAL_GENESISMETHOD
          value: file
        - name: ORDERER_FILELEDGER_LOCATION
          value: /var/hyperledger/production/orderer
        - name: ORDERER_GENERAL_GENESISFILE
          value: /var/hyperledger/orderer/scripts/genesis.block
        - name: ORDERER_GENERAL_LOCALMSPID
          value: ${ORDERER_MSP}
        - name: ORDERER_GENERAL_LOCALMSPDIR
          value: /var/hyperledger/orderer/config/msp
        - name: ORDERER_GENERAL_TLS_ENABLED
          value: \"true\"
        - name: ORDERER_GENERAL_TLS_PRIVATEKEY
          value: /var/hyperledger/orderer/config/tls/server.key
        - name: ORDERER_GENERAL_TLS_CERTIFICATE
          value: /var/hyperledger/orderer/config/tls/server.crt
        - name: ORDERER_GENERAL_TLS_ROOTCAS
          value: /var/hyperledger/orderer/config/tls/ca.crt
        - name: ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE
          value: /var/hyperledger/orderer/config/tls/server.crt
        - name: ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY
          value: /var/hyperledger/orderer/config/tls/server.key
        - name: ORDERER_GENERAL_CLUSTER_ROOTCAS
          value: /var/hyperledger/orderer/config/tls/server.crt
        - name: GODEBUG
          value: netdns=go
        volumeMounts:
        # persistent volume matches FileLedger.Location in resources/orderer/orderer.yaml or the above env
        - mountPath: /var/hyperledger/production/orderer
          name: data
        - mountPath: /var/hyperledger/orderer/config
          name: config
        - mountPath: /var/hyperledger/orderer/scripts
          name: scripts
        workingDir: /opt/gopath/src/github.com/hyperledger/fabric/orderer
      volumes:
      - name: scripts
        persistentVolumeClaim:
          claimName: scripts-orderer
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: 
      - ReadWriteOnce
      storageClassName: \"orderer-data-class\"
      resources:
        requests:
          storage: 500Mi
  - metadata:
      name: config
    spec:
      accessModes: 
      - ReadWriteOnce
      storageClassName: \"orderer-config-class\"
      resources:
        requests:
          storage: 100Mi
---
apiVersion: v1
kind: Service
# open service port for orderers, so peer/client of other orgs of different network can access
metadata:
  name: orderer-public
  namespace: ${ORG}
spec:
  type: NodePort
# use Local if service is for a single POD, so proxy will not route other PODs 
  externalTrafficPolicy: Local
  selector:
# use pod-name to restrict to a single POD
    statefulset.kubernetes.io/pod-name: orderer-0
    app: orderer
  ports:
  - protocol: TCP
    port: 7050
    targetPort: server
    nodePort: 30750"
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
          value: /etc/hyperledger/peer/config/msp
#        - name: FABRIC_CFG_PATH
#          value: /var/hyperledger/peer/config
        - name: CORE_PEER_LISTENADDRESS
          value: 0.0.0.0:7051
        - name: CORE_PEER_CHAINCODELISTENADDRESS
          value: 0.0.0.0:7052
        - name: CORE_VM_ENDPOINT
          value: unix:///host/var/run/docker.sock
#        - name: CORE_PEER_ADDRESSAUTODETECT
#          value: \"true\"
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
          value: /etc/hyperledger/peer/config/tls/server.crt
        - name: CORE_PEER_TLS_KEY_FILE
          value: /etc/hyperledger/peer/config/tls/server.key
        - name: CORE_PEER_TLS_ROOTCERT_FILE
          value: /etc/hyperledger/peer/config/tls/ca.crt
        - name: CORE_PEER_FILESYSTEMPATH
          value: /var/hyperledger/production
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
        - mountPath: /etc/hyperledger/peer/config
          name: config
      volumes:
      - name: docker-sock
        hostPath:
          path: /var/run
          type: Directory
  volumeClaimTemplates:
  - metadata:
      name: config
    spec:
      accessModes: 
      - ReadWriteOnce
      storageClassName: \"peer-config-class\"
      resources:
        requests:
          storage: 100Mi"
}

function main {
  mkdir -p ${MSP_DIR}/network
  getOrderers
  getPeers
  configPersistentData
  printNamespaceYaml > ${MSP_DIR}/network/k8s-namespace.yaml
  printOrdererStorageYaml > ${MSP_DIR}/network/k8s-orderer-pv.yaml
  printOrdererYaml > ${MSP_DIR}/network/k8s-orderer.yaml
  printPeerStorageYaml > ${MSP_DIR}/network/k8s-peer-pv.yaml
  printPeerYaml > ${MSP_DIR}/network/k8s-peer.yaml

  # start network
  kubectl create -f ${MSP_DIR}/network/k8s-namespace.yaml
  kubectl create -f ${MSP_DIR}/network/k8s-orderer-pv.yaml
  kubectl create -f ${MSP_DIR}/network/k8s-peer-pv.yaml
  kubectl create -f ${MSP_DIR}/network/k8s-orderer.yaml
  kubectl create -f ${MSP_DIR}/network/k8s-peer.yaml
}

main
