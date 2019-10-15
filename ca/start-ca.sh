#!/bin/bash
# start fabric-ca server and client for a specified org
# usage: start-ca.sh <org_name>
# where config parameters for the org are specified in ../config/org.env, e.g.
#   start-ca.sh netop1
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source $(dirname "${SCRIPT_DIR}")/config/${1:-"netop1"}.env
ORG=${FABRIC_ORG%%.*}
ORG_DIR=$(dirname "${SCRIPT_DIR}")/${FABRIC_ORG}/canet
CA_PORT=${CA_PORT:-"7054"}
TLS_PORT=${TLS_PORT:-"7055"}

# printServerService ca|tlsca
function printServerService {
  CA_NAME=${1}
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
  setServerConfig ${CA_NAME}

  echo "
  ${CN_NAME}:
    image: hyperledger/fabric-ca
    container_name: ${CN_NAME}
    ports:
    - ${PORT}:7054
    environment:
    - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server
    - FABRIC_CA_SERVER_PORT=7054
    - FABRIC_CA_SERVER_TLS_ENABLED=true
    - FABRIC_CA_SERVER_CSR_CN=${CN_NAME}
    - FABRIC_CA_SERVER_CSR_HOSTS=${CN_NAME},localhost
    volumes:
    - ./${CA_NAME}-server:/etc/hyperledger/fabric-ca-server
    command: sh -c 'fabric-ca-server start -b ${ADMIN}:${PASSWD} --tls.enabled'
    networks:
    - ${NETWORK}"
}

# setServerConfig ca|tlsca
function setServerConfig {
  CA_NAME=${1}
  SERVER_DIR="${ORG_DIR}/${CA_NAME}-server"
  mkdir -p ${SERVER_DIR}
  cp ${SCRIPT_DIR}/fabric-ca-server-config.yaml ${SERVER_DIR}/fabric-ca-server-config.yaml
  sed -i -e "s/%%admin%%/${ADMIN}/" ${SERVER_DIR}/fabric-ca-server-config.yaml
  sed -i -e "s/%%adminpw%%/${PASSWD}/" ${SERVER_DIR}/fabric-ca-server-config.yaml
  sed -i -e "s/%%country%%/${CSR_COUNTRY}/" ${SERVER_DIR}/fabric-ca-server-config.yaml
  sed -i -e "s/%%state%%/${CSR_STATE}/" ${SERVER_DIR}/fabric-ca-server-config.yaml
  sed -i -e "s/%%city%%/${CSR_CITY}/" ${SERVER_DIR}/fabric-ca-server-config.yaml
  sed -i -e "s/%%org%%/${FABRIC_ORG}/" ${SERVER_DIR}/fabric-ca-server-config.yaml
  rm ${SERVER_DIR}/fabric-ca-server-config.yaml-e
}

# printClientService - print docker yaml for ca client
function printClientService {
  CLIENT_NAME="caclient.${FABRIC_ORG}"
  mkdir -p "${ORG_DIR}/ca-client"

  echo "
  ${CLIENT_NAME}:
    image: hyperledger/fabric-ca
    container_name: ${CLIENT_NAME}
    environment:
    - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-client
    - FABRIC_CA_CLIENT_TLS_CERTFILES=/etc/hyperledger/fabric-ca-client/tls-cert.pem
    volumes:
    - ./ca-client:/etc/hyperledger/fabric-ca-client
    command: bash -c 'while true; do sleep 30; done'
    networks:
    - ${NETWORK}"
}

function printCADockerYaml {
  echo "version: '3.7'

networks:
  ${NETWORK}:

services:"
  printServerService ca
  printServerService tlsca
  printClientService
}

function main {
  # create docker yaml for CA server and client if it does not exist already
  mkdir -p "${ORG_DIR}"
  if [ ! -f "${ORG_DIR}/docker-compose.yaml" ]; then
    printCADockerYaml > ${ORG_DIR}/docker-compose.yaml
  fi

  # start CA server and client
  docker-compose -f ${ORG_DIR}/docker-compose.yaml up -d
}

main