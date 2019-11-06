#!/bin/bash
# generate crypto keys using CA server of a specified org
#   with optional ca server env, i.e., docker or k8s
# usage: bootstrap.sh <org_name> <env>
# where config parameters for the org are specified in ../config/org_name.env, e.g.
#   bootstrap.sh netop1
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
ORG_ENV=${1:-"netop1"}
ENV_TYPE=${2:-"k8s"}
source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORG_ENV} ${ENV_TYPE}

ORG=${FABRIC_ORG%%.*}
ORG_DIR=${DATA_ROOT}/canet

function genCrypto {
  ${sumd} -p ${ORG_DIR}/ca-client/caadmin
  ${sumd} -p ${ORG_DIR}/ca-client/tlsadmin

  ${sucp} $(dirname "${SCRIPT_DIR}")/config/${ORG_ENV}.env ${ORG_DIR}/ca-client/org.env
  ${sucp} ${SCRIPT_DIR}/gen-crypto.sh ${ORG_DIR}/ca-client
  ${sucp} ${ORG_DIR}/ca-server/tls-cert.pem ${ORG_DIR}/ca-client/caadmin
  ${sucp} ${ORG_DIR}/tlsca-server/tls-cert.pem ${ORG_DIR}/ca-client/tlsadmin

  # generate crypto data
  if [ "${ENV_TYPE}" == "docker" ]; then
    echo "use docker-compose"
    docker exec -w /etc/hyperledger/fabric-ca-client -it caclient.${FABRIC_ORG} bash -c './gen-crypto.sh'
  else
    echo "use k8s"
    cpod=$(kubectl get pod -l app=ca-client -o name)
    echo "generate crypto using ca-client: ${cpod##*/}"
    kubectl exec -it ${cpod##*/} -- bash -c '/etc/hyperledger/fabric-ca-client/gen-crypto.sh'
  fi
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
  echo "copy crypto for ${1}"
  CA_NAME=${1}
  TARGET=${DATA_ROOT}/crypto/${CA_NAME}
  ${sumd} -p ${TARGET}/tls

  SOURCE=${ORG_DIR}/${CA_NAME}-server
  KEYSTORE=${SOURCE}/msp/keystore
  CERTFILE=${SOURCE}/ca-cert.pem
  ${sucp} ${CERTFILE} ${TARGET}/${CA_NAME}.${FABRIC_ORG}-cert.pem
  ${sucp} ${SOURCE}/tls-cert.pem ${TARGET}/tls/server.crt
  ${sumd} -p ${DATA_ROOT}/crypto/msp/${CA_NAME}certs
  ${sucp} ${CERTFILE} ${DATA_ROOT}/crypto/msp/${CA_NAME}certs/${CA_NAME}.${FABRIC_ORG}-cert.pem

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
  tlssum=$(openssl x509 -in ${SOURCE}/tls-cert.pem -pubkey -noout -outform pem | ${CHECKSUM})
  echo "public tls key checksum: ${tlssum}"

  # find CA private key with the same public key checksum as the CA certificate
  for f in ${KEYSTORE}/*_sk; do
    echo ${f}
    sum=$(openssl pkey -in ${f} -pubout -outform pem | ${CHECKSUM})
    echo "checksum from private key: ${sum}"
    if [ "${sum}" == "${pubsum}" ]; then
      ${sucp} ${f} ${TARGET}/${CA_NAME}.${FABRIC_ORG}-key.pem
      echo "Got CA private key: ${f}"
    elif [ "${sum}" == "${tlssum}" ]; then
      ${sucp} ${f} ${TARGET}/tls/server.key
      echo "Got CA TLS private key: ${f}"
    fi
  done
}

# copyNodeCrypto <node-namme> peers|orderers|users client|server - copy crypto data of an orderer or a peer
# e.g., copyNodeCrypto peer-1 peers server
function copyNodeCrypto {
  echo "copy crypto for ${1}"
  NODE=${1}
  FOLDER=${2}
  TLSTYPE=${3}
  if [ "${FOLDER}" == "users" ]; then
    NODE_NAME=${NODE}\@${FABRIC_ORG}
    SOURCE=${ORG_DIR}/ca-client/${NODE_NAME}
    TARGET=${DATA_ROOT}/crypto/${FOLDER}/${NODE_NAME}
  else
    NODE_NAME=${NODE}.${FABRIC_ORG}
    SOURCE=${ORG_DIR}/ca-client/${NODE}
    TARGET=${DATA_ROOT}/${FOLDER}/${NODE}/crypto
  fi

  # copy msp data
  ${sumd} -p ${TARGET}/msp
  ${sucp} -R ${DATA_ROOT}/crypto/msp/cacerts ${TARGET}/msp
  ${sucp} -R ${DATA_ROOT}/crypto/msp/tlscacerts ${TARGET}/msp
  ${sucp} -R ${SOURCE}/msp/signcerts ${TARGET}/msp
  ${sucp} -R ${SOURCE}/msp/keystore ${TARGET}/msp
  ${sucp} ${DATA_ROOT}/crypto/msp/config.yaml ${TARGET}/msp
  ${sumv} ${TARGET}/msp/signcerts/cert.pem ${TARGET}/msp/signcerts/${NODE_NAME}-cert.pem

  # copy tls data
  mkdir -p ${TARGET}/tls
  ${sucp} ${DATA_ROOT}/crypto/msp/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem ${TARGET}/tls/ca.crt
  ${sucp} ${SOURCE}/tls/signcerts/cert.pem ${TARGET}/tls/${TLSTYPE}.crt
  # there should be only one file, otherwise, take the last file
  for f in ${SOURCE}/tls/keystore/*_sk; do
    ${sucp} ${f} ${TARGET}/tls/${TLSTYPE}.key
  done
}

function copyToolCrypto {
  echo "copy tools crypto"
  ${sumd} -p ${DATA_ROOT}/tool/crypto
  ${sucp} -R ${DATA_ROOT}/crypto/msp ${DATA_ROOT}/tool/crypto

  for ord in "${ORDERERS[@]}"; do
    ${sumd} -p ${DATA_ROOT}/tool/crypto/orderers/${ord}/tls
    ${sucp} ${DATA_ROOT}/orderers/${ord}/crypto/tls/server.crt ${DATA_ROOT}/tool/crypto/orderers/${ord}/tls
  done
}

function copyCliCrypto {
  echo "copy cli crypto"
  ${sumd} -p ${DATA_ROOT}/cli/crypto/${ORDERERS[0]}/msp
  ${sucp} -R ${DATA_ROOT}/orderers/${ORDERERS[0]}/crypto/msp/tlscacerts ${DATA_ROOT}/cli/crypto/${ORDERERS[0]}/msp

  for p in "${PEERS[@]}"; do
    ${sumd} -p ${DATA_ROOT}/cli/crypto/${p}
    ${sucp} -R ${DATA_ROOT}/peers/${p}/crypto/tls ${DATA_ROOT}/cli/crypto/${p}
  done

  ADMIN=${ADMIN_USER:-"Admin"}
  ${sumd} -p ${DATA_ROOT}/cli/crypto/${ADMIN}\@${FABRIC_ORG}
  ${sucp} -R ${DATA_ROOT}/crypto/users/${ADMIN}\@${FABRIC_ORG}/msp ${DATA_ROOT}/cli/crypto/${ADMIN}\@${FABRIC_ORG}
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

function cleanupCrypto {
  # cleanup target MSP folder
  for f in ca tlsca msp users; do
    echo "cleanup ${f}"
    ${surm} -R ${DATA_ROOT}/crypto/${f}
  done

  # cleanup tool and cli crypto folders
  for f in tool cli; do
    echo "cleanup ${f} crypto"
    ${surm} -R ${DATA_ROOT}/${f}/crypto
  done

  # cleanup crypto of orderers
  for ord in "${ORDERERS[@]}"; do
    echo "cleanup crypto of ${ord}"
    ${surm} -R ${DATA_ROOT}/orderers/${ord}/crypto
  done

  # cleanup crypto of peers
  for p in "${PEERS[@]}"; do
    echo "cleanup crypto of ${p}"
    ${surm} -R ${DATA_ROOT}/peers/${p}/crypto
  done
}

function collectAllCrypto {
  getOrderers
  getPeers
  cleanupCrypto

  # copy CA
  copyCACrypto ca
  copyCACrypto tlsca
  printConfigYaml > ${DATA_ROOT}/crypto/msp/config.yaml

  # copy orderers
  for ord in "${ORDERERS[@]}"; do
    copyNodeCrypto ${ord} orderers server
  done

  # copy peers
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

  # copy crypto for Tools container that bootstraps genesis block and channel tx
  copyToolCrypto

  # collect crypto for CLI container
  copyCliCrypto
}

function main {
  genCrypto
  collectAllCrypto
}

main
