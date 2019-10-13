#!/bin/bash
# generate crypto keys using CA server of a specified org
# usage: bootstrap.sh <org_name>
# it uses config parameters of the specified org as defined in ../config/org.env, e.g.
#   bootstrap.sh netop1
# using config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
ORG_ENV=$(dirname "${SCRIPT_DIR}")/config/${1:-"netop1"}.env
source ${ORG_ENV}
ORG=${FABRIC_ORG%%.*}
ORG_DIR=${SCRIPT_DIR}/${ORG}
MSP_DIR=$(dirname "${SCRIPT_DIR}")/${FABRIC_ORG}

function genCrypto {
  mkdir -p ${ORG_DIR}/ca-${ORG}-client/caadmin
  mkdir -p ${ORG_DIR}/ca-${ORG}-client/tlsadmin

  cp ${ORG_ENV} ${ORG_DIR}/ca-${ORG}-client/org.env
  cp ${SCRIPT_DIR}/gen-crypto.sh ${ORG_DIR}/ca-${ORG}-client
  cp ${ORG_DIR}/ca-${ORG}-server/tls-cert.pem ${ORG_DIR}/ca-${ORG}-client/caadmin
  cp ${ORG_DIR}/tlsca-${ORG}-server/tls-cert.pem ${ORG_DIR}/ca-${ORG}-client/tlsadmin

  # generate crypto data
  docker exec -w /etc/hyperledger/fabric-ca-client -it caclient.${FABRIC_ORG} bash -c './gen-crypto.sh'
}

function printConfigYaml {
  echo "NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/ca.${FABRIC_ORG}-cert.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/ca.${FABRIC_ORG}-cert.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/ca.${FABRIC_ORG}-cert.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/ca.${FABRIC_ORG}-cert.pem
    OrganizationalUnitIdentifier: orderer"
}

# copyCACrypto ca|tlsca
function copyCACrypto {
  CA_NAME=${1}
  TARGET=${MSP_DIR}/${CA_NAME}
  mkdir -p ${TARGET}

  SOURCE=${ORG_DIR}/${CA_NAME}-${ORG}-server
  KEYSTORE=${SOURCE}/msp/keystore
  CERTFILE=${SOURCE}/ca-cert.pem
  cp ${CERTFILE} ${TARGET}/${CA_NAME}.${FABRIC_ORG}-cert.pem
  mkdir -p ${MSP_DIR}/msp/${CA_NAME}certs
  cp ${CERTFILE} ${MSP_DIR}/msp/${CA_NAME}certs/${CA_NAME}.${FABRIC_ORG}-cert.pem

  # checksum command for Linux
  CHECKSUM=sha256sum
  hash ${CHECKSUM}
  if [ "$?" -ne 0 ]; then
    # set command for Mac
    CHECKSUM="shasum -a 256"
  fi
  echo "checksum command: $CHECKSUM"

  # calculate public key checksum from CA certificate
  pubsum=$(openssl x509 -in ${CERTFILE} -pubkey -noout -outform pem | ${CHECKSUM})
  echo "public key checksum: ${pubsum}"

  # find CA private key with the same public key checksum as the CA certificate
  for f in ${KEYSTORE}/*_sk; do
    echo ${f}
    sum=$(openssl pkey -in ${f} -pubout -outform pem | ${CHECKSUM})
    echo "checksum from private key: ${sum}"
    if [ "${sum}" == "${pubsum}" ]; then
      cp ${f} ${TARGET}
      echo "Got CA private key: ${f}"
      break
    fi
  done
}

# copyNodeCrypto <node-namme> peers|orderers|users client|server - copy crypto data of an orderer or a peer
# e.g., copyNodeCrypto peer-1 peers server
function copyNodeCrypto {
  NODE=${1}
  FOLDER=${2}
  TLSTYPE=${3}
  if [ "${FOLDER}" == "users" ]; then
    NODE_NAME=${NODE}\@${FABRIC_ORG}
    SOURCE=${ORG_DIR}/ca-${ORG}-client/${NODE_NAME}
    TARGET=${MSP_DIR}/${FOLDER}/${NODE_NAME}
  else
    NODE_NAME=${NODE}.${FABRIC_ORG}
    SOURCE=${ORG_DIR}/ca-${ORG}-client/${NODE}
    TARGET=${MSP_DIR}/${FOLDER}/${NODE_NAME}
  fi

  # copy msp data
  mkdir -p ${TARGET}/msp
  cp -R ${MSP_DIR}/msp/cacerts ${TARGET}/msp
  cp -R ${MSP_DIR}/msp/tlscacerts ${TARGET}/msp
  cp -R ${SOURCE}/msp/signcerts ${TARGET}/msp
  cp -R ${SOURCE}/msp/keystore ${TARGET}/msp
  cp ${MSP_DIR}/msp/config.yaml ${TARGET}/msp
  mv ${TARGET}/msp/signcerts/cert.pem ${TARGET}/msp/signcerts/${NODE_NAME}-cert.pem

  # copy tls data
  mkdir -p ${TARGET}/tls
  cp ${MSP_DIR}/msp/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem ${TARGET}/tls/ca.crt
  cp ${SOURCE}/tls/signcerts/cert.pem ${TARGET}/tls/${TLSTYPE}.crt
  for f in ${SOURCE}/tls/keystore/*_sk; do
    cp ${f} ${TARGET}/tls/${TLSTYPE}.key
  done
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

function collectAllCrypto {
  # cleanup target MSP folder
  rm -R ${MSP_DIR}

  # copy CA 
  copyCACrypto ca
  copyCACrypto tlsca
  printConfigYaml > ${MSP_DIR}/msp/config.yaml

  # copy orderers
  getOrderers
  for ord in "${ORDERERS[@]}"; do
    copyNodeCrypto ${ord} orderers server
  done

  # copy peers
  getPeers
  for p in "${PEERS[@]}"; do
    copyNodeCrypto ${p} peers server
  done

  # copy admin user
  copyNodeCrypto ${ADMIN_USER:-"Admin"} users server

  # copy other users
  if [ ! -z "${USERS}" ]; then
    for u in ${USERS}; do
      copyNodeCrypto ${u} users client
    done
  fi
}

function main {
  genCrypto
  collectAllCrypto
}

main
