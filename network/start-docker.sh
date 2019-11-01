#!/bin/bash
# create and start fabric network of docker-compose for docker-compose
# usage: start-docker.sh <org_name>
# it uses config parameters of the specified org as defined in ../config/org.env, e.g.
#   start-docker.sh netop1
# using config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${1:-"netop1"} docker

ORG_MSP="${ORG}MSP"
ORDERER_MSP=${ORDERER_MSP:-"${ORG}OrdererMSP"}

SYS_CHANNEL=${SYS_CHANNEL:-"${ORG}-channel"}
TEST_CHANNEL=${TEST_CHANNEL:-"mychannel"}
ORDERER_TYPE=${ORDERER_TYPE:-"solo"}
ORDERER_PORT=${ORDERER_PORT:-"7050"}
PEER_PORT=${PEER_PORT:-"7051"}

COUCHDB_USER=${COUCHDB_USER:-""}
COUCHDB_PASSWD=${COUCHDB_PASSWD:-""}
COUCHDB_PORT=${COUCHDB_PORT:-"7056"}

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

# set list of couchdbs corresponding to peers
function getCouchdbs {
  COUCHDBS=()
  seq=${PEER_MIN:-"0"}
  max=${PEER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    COUCHDBS+=("couchdb-${seq}")
    seq=$((${seq}+1))
  done
}

# printCAService ca|tlsca
function printCAService {
  CA_NAME=${1}
  CN_NAME="${CA_NAME}.${FABRIC_ORG}"
  if [ "${CA_NAME}" == "tlsca" ]; then
    PORT=${TLS_PORT:-"7055"}
    ADMIN=${TLS_ADMIN:-"tlsadmin"}
    PASSWD=${TLS_PASSWD:-"tlsadminpw"}
  else
    PORT=${CA_PORT:-"7054"}
    ADMIN=${CA_ADMIN:-"caadmin"}
    PASSWD=${CA_PASSWD:-"caadminpw"}
  fi

  echo "
  ${CN_NAME}:
    image: hyperledger/fabric-ca
    container_name: ${CN_NAME}
    ports:
    - ${PORT}:7054
    environment:
    - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server
    - FABRIC_CA_SERVER_CA_NAME=${CN_NAME}
    - FABRIC_CA_SERVER_PORT=7054
    - FABRIC_CA_SERVER_CA_CERTFILE=/etc/hyperledger/fabric-ca-server-config/${CA_NAME}.${FABRIC_ORG}-cert.pem
    - FABRIC_CA_SERVER_CA_KEYFILE=/etc/hyperledger/fabric-ca-server-config/${CA_NAME}.${FABRIC_ORG}-key.pem
    - FABRIC_CA_SERVER_TLS_ENABLED=true
    - FABRIC_CA_SERVER_TLS_CERTFILE=/etc/hyperledger/fabric-ca-server-config/tls/server.crt
    - FABRIC_CA_SERVER_TLS_KEYFILE=/etc/hyperledger/fabric-ca-server-config/tls/server.key
    volumes:
    - ${DATA_ROOT}/crypto/${CA_NAME}/:/etc/hyperledger/fabric-ca-server-config
    command: sh -c 'fabric-ca-server start -b ${ADMIN}:${PASSWD}'
    networks:
    - ${ORG}"
}

function printCADockerYaml {
  echo "version: '2'

networks:
  ${ORG}:

services:"
  printCAService ca
  printCAService tlsca
}

# printOrdererService <seq>
# orderer data are persisted by named volume, e.g., orderer-0.netop1.com
# by default, it is set in orderer.yaml or env ORDERER_GENERAL_FILELEDGER_LOCATION=/var/hyperledger/production/orderer
# the named volume on localhost is under /var/lib/docker/volumes/docker_orderer-0.netop1.com
# On Mac, this volume exists in 'docker-desktop' VM, and can only be viewed after login to the VM via 'screen'
function printOrdererService {
  ord=${ORDERERS[${1}]}
  PORT=$((${1} * 10 + ${ORDERER_PORT}))
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
        - ${DATA_ROOT}/artifacts/genesis.block:/var/hyperledger/orderer/orderer.genesis.block
        - ${DATA_ROOT}/crypto/orderers/${ord}.${FABRIC_ORG}/msp:/var/hyperledger/orderer/msp
        - ${DATA_ROOT}/crypto/orderers/${ord}.${FABRIC_ORG}/tls/:/var/hyperledger/orderer/tls
        - ${ord}.${FABRIC_ORG}:/var/hyperledger/production/orderer
    ports:
      - ${PORT}:7050
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
  p=${PEERS[${1}]}
  PORT=$((${1} * 10 + ${PEER_PORT}))

  gossip_peer=${PEERS[0]}
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
        - ${DATA_ROOT}/crypto/peers/${p}.${FABRIC_ORG}/msp:/etc/hyperledger/fabric/msp
        - ${DATA_ROOT}/crypto/peers/${p}.${FABRIC_ORG}/tls/:/etc/hyperledger/fabric/tls
        - ${p}.${FABRIC_ORG}:/var/hyperledger/production
    ports:
      - ${PORT}:7051
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
  db=${COUCHDBS[${1}]}
  db_port=$((${1} * 10 + ${COUCHDB_PORT}))
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
      - ${db_port}:5984
    networks:
      - ${ORG}"
}

# cli container is used to create channel, instantiate chaincode, and check status, e.g.,
# docker exec -it cli bash
# peer channel list
# peer chaincode list -C mychannel --instantiated
function printCliService {
  admin=${ADMIN_USER:-"Admin"}
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
      - CORE_PEER_TLS_CERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/${PEERS[0]}.${FABRIC_ORG}/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/${PEERS[0]}.${FABRIC_ORG}/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/${PEERS[0]}.${FABRIC_ORG}/tls/ca.crt
      - CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/${admin}@${FABRIC_ORG}/msp
      - ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/${ORDERERS[0]}.${FABRIC_ORG}/msp/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem
      - ORDERER_URL=${ORDERERS[0]}.${FABRIC_ORG}:7050
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    command: /bin/bash
    volumes:
      - /var/run/:/host/var/run/
      - ${DATA_ROOT}/artifacts/:/opt/gopath/src/github.com/hyperledger/fabric/peer/artifacts/
      - ${DATA_ROOT}/crypto/cli/:/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/
      - ${DATA_ROOT}/chaincode/:/opt/gopath/src/github.com/chaincode:cached
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

function main {
  mkdir -p ${DATA_ROOT}/network/docker
  COMPOSE_FILES="-f ${DATA_ROOT}/network/docker/docker-compose.yaml"

  # no need to start ca server and client here !!
  # if [ ! -z "${CA_PORT}" ]; then
  #   COMPOSE_FILES="${COMPOSE_FILES} -f ${DATA_ROOT}/network/docker/docker-compose-ca.yaml"
  # fi

  # create docker yaml if it does not exist already
  if [ ! -f "${DATA_ROOT}/network/docker/docker-compose.yaml" ]; then
    # print CA server yaml
    echo "create ${DATA_ROOT}/network/docker/docker-compose-ca.yaml ..."
    printCADockerYaml > ${DATA_ROOT}/network/docker/docker-compose-ca.yaml

    # print orderer, peer, cli yaml
    echo "create ${DATA_ROOT}/network/docker/docker-compose.yaml ..."
    printNetworkDockerYaml > ${DATA_ROOT}/network/docker/docker-compose.yaml
  fi

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

  docker-compose ${COMPOSE_FILES} up -d
}

main
