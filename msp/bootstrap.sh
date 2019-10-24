#!/bin/bash
# create MSP configuration, channel profile, and orderer genesis block
#   for target environment, i.e., docker, k8s, aws, etc
# usage: bootstrap.sh <org_name> <env>
# it uses config parameters of the specified org as defined in ../config/org.env, e.g.
#   bootstrap.sh netop1
# using config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source $(dirname "${SCRIPT_DIR}")/network/setup.sh ${1:-"netop1"} ${2:-"docker"}

MSP_DIR=$(dirname "${SCRIPT_DIR}")/${FABRIC_ORG}
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
        MSPDir: ../msp
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
        MSPDir: ../msp
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
                  ClientTLSCert: ../orderers/${ord}.${FABRIC_ORG}/tls/server.crt
                  ServerTLSCert: ../orderers/${ord}.${FABRIC_ORG}/tls/server.crt"
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

function printToolDockerYaml {
  echo "version: '3.7'

services:
  tool:
    container_name: tool
    image: hyperledger/fabric-tools
    tty: true
    stdin_open: true
    environment:
      - ORG=${ORG}
      - SYS_CHANNEL=${SYS_CHANNEL}
      - TEST_CHANNEL=${TEST_CHANNEL}
      - ORDERER_TYPE=${ORDERER_TYPE}
      - FABRIC_CFG_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/config/artifacts
      - GOPATH=/opt/gopath
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      #- FABRIC_LOGGING_SPEC=DEBUG
      - FABRIC_LOGGING_SPEC=INFO
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    command: /bin/bash -c 'cd config/artifacts && ./gen-config-block.sh'
    volumes:
        - /var/run/:/host/var/run/
        - ./../:/opt/gopath/src/github.com/hyperledger/fabric/peer/config/
    networks:
    - ${ORG}

networks:
  ${ORG}:
"
}

# generate orderer genesis block and tx for creating test channel
function gen-config {
  # print out configtx.yaml
  mkdir -p ${MSP_DIR}/artifacts
  printConfigTx > ${MSP_DIR}/artifacts/configtx.yaml

  # start tool container to generate genesis block and channel tx
  printToolDockerYaml > ${MSP_DIR}/artifacts/docker-compose.yaml
  cp ${SCRIPT_DIR}/gen-config-block.sh ${MSP_DIR}/artifacts
  docker-compose -f ${MSP_DIR}/artifacts/docker-compose.yaml up

  # cleanup tool container and docker network
  docker network rm artifacts_${ORG}
  docker rm tool
}

function main {
  gen-config
}

main
