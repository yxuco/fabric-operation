#!/bin/bash
# start fabric-ca server and client for a specified org
# usage: start-ca.sh <org_name>
# where config parameters for the org are specified in ../config/org.env, e.g.
#   start-ca.sh netop1
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source $(dirname "${SCRIPT_DIR}")/config/${1:-"netop1"}.env
ORG=${FABRIC_ORG%%.*}
ORG_DIR=${SCRIPT_DIR}/${ORG}
CA_PORT=${CA_PORT:-"7054"}
TLS_PORT=${TLS_PORT:-"7055"}

# printServerDockerYaml init|start ca|tlsca
# e.g., printServerDockerYaml start tlsca
function printServerDockerYaml {
  CMD=${1}
  CA_NAME=${2}
  if [ "${CA_NAME}" == "tlsca" ]; then
    PORT=${TLS_PORT}
    ADMIN=${TLS_ADMIN:-"admin"}
    PASSWD=${TLS_PASSWD:-"adminpw"}
  else
    PORT=${CA_PORT}
    ADMIN=${CA_ADMIN:-"admin"}
    PASSWD=${CA_PASSWD:-"adminpw"}
  fi

  CN_NAME="${CA_NAME}.${FABRIC_ORG}"
  CONFIG_DIR="${CA_NAME}-${ORG}-server"

  echo "version: '3.7'

services:
  ${CN_NAME}:
    image: hyperledger/fabric-ca
    container_name: ${CN_NAME}
    ports:
    - ${PORT}:7054
    environment:
    - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server
    - FABRIC_CA_SERVER_TLS_ENABLED=true
    - FABRIC_CA_SERVER_CSR_CN=${CN_NAME}
    - FABRIC_CA_SERVER_CSR_HOSTS=${CN_NAME},localhost
    volumes:
    - ${ORG_DIR}/${CONFIG_DIR}:/etc/hyperledger/fabric-ca-server
    command: sh -c 'fabric-ca-server ${CMD} -b ${ADMIN}:${PASSWD} -p 7054 --tls.enabled'
    networks:
    - ${NETWORK}

networks:
  ${NETWORK}:
"
}

# printClientDockerYaml - print docker yaml for ca client
function printClientDockerYaml {
  CLIENT_NAME="caclient.${FABRIC_ORG}"
  CLIENT_DIR="ca-${ORG}-client"

  echo "version: '3.7'

services:
  ${CLIENT_NAME}:
    image: hyperledger/fabric-ca
    container_name: ${CLIENT_NAME}
    environment:
    - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-client
    - FABRIC_CA_CLIENT_TLS_CERTFILES=/etc/hyperledger/fabric-ca-client/tls-cert.pem
    volumes:
    - ${ORG_DIR}/${CLIENT_DIR}:/etc/hyperledger/fabric-ca-client
    command: bash -c 'while true; do sleep 30; done'
    networks:
    - ${NETWORK}

networks:
  ${NETWORK}:
"
}

# configCA ca|tlsca
# e.g., configCA ca
function configCA {
  CA_NAME=${1}
  mkdir -p ${ORG_DIR}

  # initialize CA server config with specified Org name in CA certificate
  printServerDockerYaml init ${CA_NAME} > ${ORG_DIR}/init-${CA_NAME}-${ORG}.yaml
  docker-compose -f ${ORG_DIR}/init-${CA_NAME}-${ORG}.yaml up
  sed "s/O: Hyperledger/O: ${FABRIC_ORG}/g" ${ORG_DIR}/${CA_NAME}-${ORG}-server/fabric-ca-server-config.yaml > ${ORG_DIR}/fabric-ca-server-config.yaml
  rm -R ${ORG_DIR}/${CA_NAME}-${ORG}-server/*
  sed "s/OU: Fabric//g" ${ORG_DIR}/fabric-ca-server-config.yaml > ${ORG_DIR}/${CA_NAME}-${ORG}-server/fabric-ca-server-config.yaml

  # cleanup files from CA init
  rm ${ORG_DIR}/fabric-ca-server-config.yaml
  rm ${ORG_DIR}/init-${CA_NAME}-${ORG}.yaml
  docker rm ${CA_NAME}.${FABRIC_ORG}

  # create CA server docker-compose yaml
  printServerDockerYaml start ${CA_NAME} > ${ORG_DIR}/${CA_NAME}-${ORG}-server.yaml
}

# start TLS and CA servers and a CA client for the configured FABRIC_ORG
function startCA {
  if [ ! -f "${ORG_DIR}/tlsca-${ORG}-server.yaml" ]; then
    # config TLS CA server
    configCA tlsca
  fi

  if [ ! -f "${ORG_DIR}/ca-${ORG}-client.yaml" ]; then
    # config CA client
    printClientDockerYaml > ${ORG_DIR}/ca-${ORG}-client.yaml
    mkdir -p ${ORG_DIR}/ca-${ORG}-client
  fi

  if [ ! -f "${ORG_DIR}/ca-${ORG}-server.yaml" ]; then
    # config CA server
    configCA ca
  fi

  # start CA server and client
  docker-compose -f ${ORG_DIR}/tlsca-${ORG}-server.yaml -f ${ORG_DIR}/ca-${ORG}-server.yaml -f ${ORG_DIR}/ca-${ORG}-client.yaml up -d
}

function main {
  startCA
}

main