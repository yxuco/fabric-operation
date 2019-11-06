#!/bin/bash
# create MSP configuration, channel profile, and orderer genesis block
#   for target environment, i.e., docker, k8s, aws, etc
# usage: bootstrap.sh <org_name> <env>
# it uses config parameters of the specified org as defined in ../config/org.env, e.g.
#   bootstrap.sh netop1
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

function printOrdererMSP {
  if [ "${#ORDERERS[@]}" -gt "0" ]; then
    echo "
    - &${ORDERER_MSP}
        Name: ${ORDERER_MSP}
        ID: ${ORDERER_MSP}
        MSPDir: /etc/hyperledger/tool/crypto/msp
        Policies:
            Readers:
                Type: Signature
                Rule: \"OR('${ORDERER_MSP}.member')\"
            Writers:
                Type: Signature
                Rule: \"OR('${ORDERER_MSP}.member')\"
            Admins:
                Type: Signature
                Rule: \"OR('${ORDERER_MSP}.admin')\""
  fi
}

function printPeerMSP {
  echo "
    - &${ORG_MSP}
        Name: ${ORG_MSP}
        ID: ${ORG_MSP}
        MSPDir: /etc/hyperledger/tool/crypto/msp
        Policies:
            Readers:
                Type: Signature
                Rule: \"OR('${ORG_MSP}.admin', '${ORG_MSP}.peer', '${ORG_MSP}.client')\"
            Writers:
                Type: Signature
                Rule: \"OR('${ORG_MSP}.admin', '${ORG_MSP}.client')\"
            Admins:
                Type: Signature
                Rule: \"OR('${ORG_MSP}.admin')\""
  if [ "${#PEERS[@]}" -gt "0" ]; then
    echo "
        AnchorPeers:
            - Host: $(getHostUrl ${PEERS[0]})
              Port: 7051"
  fi
}

function printCapabilities {
  echo "
Capabilities:
    Channel: &ChannelCapabilities
        V1_4_3: true
        V1_3: false
        V1_1: false
    Orderer: &OrdererCapabilities
        V1_4_2: true
        V1_1: false
    Application: &ApplicationCapabilities
        V1_4_2: true
        V1_3: false
        V1_2: false
        V1_1: false"
}

function printApplicationDefaults {
  echo "
Application: &ApplicationDefaults
    Organizations:
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        Admins:
            Type: ImplicitMeta
            Rule: \"MAJORITY Admins\"

    Capabilities:
        <<: *ApplicationCapabilities"
}

function printOrdererDefaults {
  if [ "${#ORDERERS[@]}" -gt "0" ]; then
    echo "
Orderer: &OrdererDefaults
    OrdererType: solo
    Addresses:
        - $(getHostUrl ${ORDERERS[0]}):7050
    BatchTimeout: 2s
    BatchSize:
        MaxMessageCount: 10
        AbsoluteMaxBytes: 99 MB
        PreferredMaxBytes: 512 KB
    Organizations:

    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        Admins:
            Type: ImplicitMeta
            Rule: \"MAJORITY Admins\"
        BlockValidation:
            Type: ImplicitMeta
            Rule: \"ANY Writers\""
  fi
}

function printChannelDefaults {
  echo "
Channel: &ChannelDefaults
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        Admins:
            Type: ImplicitMeta
            Rule: \"MAJORITY Admins\"
    Capabilities:
        <<: *ChannelCapabilities"
}

function printOrgConsortium {
  echo "
        Consortiums:
            ${ORG}Consortium:
                Organizations:
                    - *${ORG_MSP}"
}

function printSoloOrdererProfile {
  if [ "${#ORDERERS[@]}" -gt "0" ]; then
    echo "
    soloOrdererGenesis:
        <<: *ChannelDefaults
        Orderer:
            <<: *OrdererDefaults
            Organizations:
                - *${ORDERER_MSP}
            Capabilities:
                <<: *OrdererCapabilities"
    printOrgConsortium
  fi
}

function printEtcdraftOrdererProfile {
  if [ "${#ORDERERS[@]}" -gt "0" ]; then
    echo "
    etcdraftOrdererGenesis:
        <<: *ChannelDefaults
        Capabilities:
            <<: *ChannelCapabilities
        Orderer:
            <<: *OrdererDefaults
            OrdererType: etcdraft
            EtcdRaft:
                Consenters:"
    for ord in "${ORDERERS[@]}"; do
      echo "                - Host: $(getHostUrl ${ord})
                  Port: 7050
                  ClientTLSCert: /etc/hyperledger/tool/crypto/orderers/${ord}/tls/server.crt
                  ServerTLSCert: /etc/hyperledger/tool/crypto/orderers/${ord}/tls/server.crt"
    done
    echo "            Addresses:"
    for ord in "${ORDERERS[@]}"; do
      echo "                - $(getHostUrl ${ord}):7050"
    done
    echo "            Organizations:
                - *${ORDERER_MSP}
            Capabilities:
                <<: *OrdererCapabilities
        Application:
            <<: *ApplicationDefaults
            Organizations:
            - <<: *${ORDERER_MSP}"
    printOrgConsortium
  fi
}

function printOrgChannelProfile {
  echo "
    ${ORG}Channel:
        Consortium: ${ORG}Consortium
        <<: *ChannelDefaults
        Application:
            <<: *ApplicationDefaults
            Organizations:
                - *${ORG_MSP}
            Capabilities:
                <<: *ApplicationCapabilities"
}

function printConfigTx {
  getOrderers
  getPeers

  echo "---
Organizations:"
  printOrdererMSP
  printPeerMSP

  printCapabilities
  printApplicationDefaults
  printOrdererDefaults
  printChannelDefaults

  echo "
Profiles:"
  printSoloOrdererProfile
  printEtcdraftOrdererProfile
  printOrgChannelProfile
}

function printDockerYaml {
  echo "version: '3.7'

services:
  tool:
    container_name: tool
    image: hyperledger/fabric-tools
    tty: true
    stdin_open: true
    environment:
      - FABRIC_CFG_PATH=/etc/hyperledger/tool
      - GOPATH=/opt/gopath
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - FABRIC_LOGGING_SPEC=INFO
    working_dir: /etc/hyperledger/tool
    command: /bin/bash -c \"
        configtxgen -profile ${ORDERER_TYPE}OrdererGenesis -channelID ${SYS_CHANNEL} -outputBlock ./genesis.block
        && configtxgen -profile ${ORG}Channel -outputCreateChannelTx ./channel.tx -channelID ${TEST_CHANNEL}
        && configtxgen -profile ${ORG}Channel -outputAnchorPeersUpdate ./anchors.tx -channelID ${TEST_CHANNEL} -asOrg ${ORG_MSP}
      \"
    volumes:
        - /var/run/:/host/var/run/
        - ${DATA_ROOT}/tool/:/etc/hyperledger/tool
    networks:
    - ${ORG}

networks:
  ${ORG}:
"
}

# printK8sStorageClass <name>
# storage class for local host, or AWS EFS
function printK8sStorageClass {
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
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer"

  if [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo "parameters:
  skuName: Standard_LRS"
  fi
}

# print k8s PV and PVC for tool Job
function printK8sStorageYaml {
  printK8sStorageClass "tool-data-class"
  printK8sPV "data-tool"
}

# printK8sPV <name>
function printK8sPV {
  echo "---
kind: PersistentVolume
apiVersion: v1
# create PV for ${1}
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
  storageClassName: tool-data-class"

  if [ "${K8S_PERSISTENCE}" == "efs" ]; then
    echo "  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${AWS_FSID}
    volumeAttributes:
      path: /${FABRIC_ORG}/tool"
  elif [ "${K8S_PERSISTENCE}" == "azf" ]; then
    echo"  azureFile:
    secretName: azure-secret
    shareName: ${AZ_STORAGE_SHARE}/${FABRIC_ORG}/tool
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
    path: ${DATA_ROOT}/tool
    type: Directory"
  fi

  echo "---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ${1}-pvc
  namespace: ${ORG}
spec:
  storageClassName: tool-data-class
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

function printK8sJob {
  echo "
apiVersion: batch/v1
kind: Job
metadata:
  name: tool
  namespace: ${ORG}
  labels:
    app: tool
spec:
#  selector:
#    matchLabels:
#      app: tool
  backoffLimit: 3
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels:
        app: tool
    spec:
      containers:
      - name: tool
        image: hyperledger/fabric-tools
        env:
        - name: FABRIC_LOGGING_SPEC
          value: INFO
        - name: GOPATH
          value: /opt/gopath
        - name: FABRIC_CFG_PATH
          value: /etc/hyperledger/tool
        - name: CORE_VM_ENDPOINT
          value: unix:///host/var/run/docker.sock
        command:
        - /bin/bash
        - -c
        - |
          configtxgen -profile ${ORDERER_TYPE}OrdererGenesis -channelID ${SYS_CHANNEL} -outputBlock ./genesis.block
          configtxgen -profile ${ORG}Channel -outputCreateChannelTx ./channel.tx -channelID ${TEST_CHANNEL}
          configtxgen -profile ${ORG}Channel -outputAnchorPeersUpdate ./anchors.tx -channelID ${TEST_CHANNEL} -asOrg ${ORG_MSP}
        workingDir: /etc/hyperledger/tool
        volumeMounts:
        - mountPath: /host/var/run
          name: docker-sock
        - mountPath: /etc/hyperledger/tool
          name: data
      restartPolicy: Never
      volumes:
      - name: docker-sock
        hostPath:
          path: /var/run
          type: Directory
      - name: data
        persistentVolumeClaim:
          claimName: data-tool-pvc"
}

function runK8s {
  echo "use kubernetes"
  # print k8s yaml for tool job
  ${sumd} -p "${DATA_ROOT}/tool/k8s"
  printK8sStorageYaml | ${stee} ${DATA_ROOT}/tool/k8s/tool-pv.yaml > /dev/null
  printK8sJob | ${stee} ${DATA_ROOT}/tool/k8s/tool.yaml > /dev/null

  # run tool job
  kubectl create -f ${DATA_ROOT}/tool/k8s/tool-pv.yaml
  kubectl create -f ${DATA_ROOT}/tool/k8s/tool.yaml
}

function runDocker {
  echo "use docker-compose"
  # start tool container to generate genesis block and channel tx
  mkdir -p "${DATA_ROOT}/tool/docker"
  printDockerYaml > ${DATA_ROOT}/tool/docker/docker-compose.yaml
  docker-compose -f ${DATA_ROOT}/tool/docker/docker-compose.yaml up

  # cleanup tool container and docker network
  docker network rm docker_${ORG}
  docker rm tool
}

# generate orderer genesis block and tx for creating test channel
function main {
  # print out configtx.yaml
  echo "create ${DATA_ROOT}/tool/configtx.yaml"
  printConfigTx > ${DATA_ROOT}/tool/configtx.yaml

  if [ "${ENV_TYPE}" == "docker" ]; then
    runDocker
  else
    runK8s
  fi
}

main
