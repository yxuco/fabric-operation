#!/bin/bash
# generate crypto keys using CA server of a specified org, and ca server env, i.e., docker or k8s
# ca-crypto.sh <cmd> [-p <property file>] [-t <env type>] [-s <start seq>] [-e <end seq>] [-u <user name>]
# where property file for the org are specified in ../config/org_name.env, e.g.
#   ca-crypto.sh bootstrap -p netop1
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"

# genCrypto <args>
# args are passed to gen-crypto.sh for ca-client
function genCrypto {
  ${sumd} -p ${ORG_DIR}/ca-client/caadmin
  ${sumd} -p ${ORG_DIR}/ca-client/tlsadmin

  ${sucp} $(dirname "${SCRIPT_DIR}")/config/${ORG_ENV}.env ${ORG_DIR}/ca-client/org.env
  ${sucp} ${SCRIPT_DIR}/gen-crypto.sh ${ORG_DIR}/ca-client
  ${sucp} ${ORG_DIR}/ca-server/tls-cert.pem ${ORG_DIR}/ca-client/caadmin
  ${sucp} ${ORG_DIR}/tlsca-server/tls-cert.pem ${ORG_DIR}/ca-client/tlsadmin

  # generate crypto data
  local _cmd="gen-crypto.sh $@"
  if [ "${ENV_TYPE}" == "docker" ]; then
    echo "use docker-compose - ${_cmd}"
    docker exec -w /etc/hyperledger/fabric-ca-client -it caclient.${FABRIC_ORG} bash -c "./${_cmd}"
  else
    echo "use k8s - ${_cmd}"
    cpod=$(kubectl get pod -l app=ca-client -o name)
    if [ -z "${cpod}" ]; then
      echo "Error: ca-client is not running, start ca server and client first"
      exit 1
    else
      echo "generate crypto using ca-client: ${cpod##*/}"
      kubectl exec -it ${cpod##*/} -- bash -c "./${_cmd}"
    fi
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
  local _ca=${1}
  local _target=${DATA_ROOT}/crypto/${_ca}
  ${sumd} -p ${_target}/tls

  local _src=${ORG_DIR}/${_ca}-server
  ${sucp} ${_src}/ca-cert.pem ${_target}/${_ca}.${FABRIC_ORG}-cert.pem
  ${sucp} ${_src}/tls-cert.pem ${_target}/tls/server.crt
  ${sumd} -p ${DATA_ROOT}/crypto/msp/${_ca}certs
  ${sucp} ${_src}/ca-cert.pem ${DATA_ROOT}/crypto/msp/${_ca}certs/${_ca}.${FABRIC_ORG}-cert.pem

  # checksum command for Linux
  CHECKSUM=sha256sum
  hash ${CHECKSUM}
  if [ "$?" -ne 0 ]; then
    # set command for Mac
    CHECKSUM="shasum -a 256"
  fi
  echo "checksum command: $CHECKSUM"

  # calculate public key checksum from CA certificate
  pubsum=$(openssl x509 -in ${_src}/ca-cert.pem -pubkey -noout -outform pem | ${CHECKSUM})
  echo "public key checksum: ${pubsum}"
  tlssum=$(openssl x509 -in ${_src}/tls-cert.pem -pubkey -noout -outform pem | ${CHECKSUM})
  echo "public tls key checksum: ${tlssum}"

  # find CA private key with the same public key checksum as the CA certificate
  local s=""
  if [ "${ENV_TYPE}" == "aws" ]; then
    s="sudo "
  fi
  for f in ${_src}/msp/keystore/*_sk; do
    echo ${f}
    sum=$(${s}openssl pkey -in ${f} -pubout -outform pem | ${CHECKSUM})
    echo "checksum from private key: ${sum}"
    if [ "${sum}" == "${pubsum}" ]; then
      ${sucp} ${f} ${_target}/${_ca}.${FABRIC_ORG}-key.pem
      echo "Got CA private key: ${f}"
    elif [ "${sum}" == "${tlssum}" ]; then
      ${sucp} ${f} ${_target}/tls/server.key
      echo "Got CA TLS private key: ${f}"
    fi
  done
}

# copyOrdererCrypto [1 2]
function copyOrdererCrypto {
  local _seq=$1
  local _max=$2

  if [ -z "${_seq}" ]; then
    # no orderer specified, so copy all orderers defined in network spec
    _seq=${ORDERER_MIN:-"0"}
    _max=${ORDERER_MAX:-"0"}
  elif [ -z "${_max}" ]; then
    # copy only 1 orderer if max seq is not specified
    _max=$((${_seq}+1))
  fi

  until [ "${_seq}" -ge "${_max}" ]; do
    local _orderer="orderer-${_seq}"
    _seq=$((${_seq}+1))
    copyNodeCrypto ${_orderer} orderers server
  done
}

# copyPeerCrypto [1 2]
function copyPeerCrypto {
  local _seq=$1
  local _max=$2

  if [ -z "${_seq}" ]; then
    # no peer specified, so copy all peers defined in network spec
    _seq=${PEER_MIN:-"0"}
    _max=${PEER_MAX:-"0"}
  elif [ -z "${_max}" ]; then
    # copy only 1 peer if max seq is not specified
    _max=$((${_seq}+1))
  fi

  until [ "${_seq}" -ge "${_max}" ]; do
    local _peer="peer-${_seq}"
    _seq=$((${_seq}+1))
    copyNodeCrypto ${_peer} peers server
  done
}

# copyNodeCrypto <node-namme> peers|orderers|users client|server - copy crypto data of an orderer or a peer
# e.g., copyNodeCrypto peer-1 peers server
function copyNodeCrypto {
  echo "copy crypto for ${1}"
  local _name=${1}.${FABRIC_ORG}
  local _src=${ORG_DIR}/ca-client/${1}
  local _target=${DATA_ROOT}/${2}/${1}/crypto
  if [ "${2}" == "users" ]; then
    _name=${1}\@${FABRIC_ORG}
    _src=${ORG_DIR}/ca-client/${_name}
    _target=${DATA_ROOT}/crypto/${2}/${_name}
  fi

  if [ "${ENV_TYPE}" == "aws" ]; then
    sudo chmod -R 755 ${_src}
  fi

  # copy msp data
  ${sumd} -p ${_target}/msp
  ${sucp} -R ${DATA_ROOT}/crypto/msp/cacerts ${_target}/msp
  ${sucp} -R ${DATA_ROOT}/crypto/msp/tlscacerts ${_target}/msp
  ${sucp} -R ${_src}/msp/signcerts ${_target}/msp
  ${sucp} -R ${_src}/msp/keystore ${_target}/msp
  ${sucp} ${DATA_ROOT}/crypto/msp/config.yaml ${_target}/msp
  ${sumv} ${_target}/msp/signcerts/cert.pem ${_target}/msp/signcerts/${_name}-cert.pem

  # copy tls data
  ${sumd} -p ${_target}/tls
  ${sucp} ${DATA_ROOT}/crypto/msp/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem ${_target}/tls/ca.crt
  ${sucp} ${_src}/tls/signcerts/cert.pem ${_target}/tls/${3}.crt
  # there should be only one file, otherwise, take the last file
  for f in ${_src}/tls/keystore/*_sk; do
    ${sucp} ${f} ${_target}/tls/${3}.key
  done
}

function copyToolCrypto {
  echo "copy tools crypto"
  ${sumd} -p ${DATA_ROOT}/tool/crypto
  ${sucp} -R ${DATA_ROOT}/crypto/msp ${DATA_ROOT}/tool/crypto

  local _seq=${ORDERER_MIN:-"0"}
  local _max=${ORDERER_MAX:-"0"}
  until [ "${_seq}" -ge "${_max}" ]; do
    local _orderer="orderer-${_seq}"
    _seq=$((${_seq}+1))
    ${sumd} -p ${DATA_ROOT}/tool/crypto/orderers/${_orderer}/tls
    ${sucp} ${DATA_ROOT}/orderers/${_orderer}/crypto/tls/server.crt ${DATA_ROOT}/tool/crypto/orderers/${_orderer}/tls
  done
}

function copyCliCrypto {
  echo "copy cli crypto"
  local _ord0="orderer-${ORDERER_MIN:-"0"}"
  ${sumd} -p ${DATA_ROOT}/cli/crypto/${_ord0}/msp
  ${sucp} -R ${DATA_ROOT}/orderers/${_ord0}/crypto/msp/tlscacerts ${DATA_ROOT}/cli/crypto/${_ord0}/msp

  local _seq=${PEER_MIN:-"0"}
  local _max=${PEER_MAX:-"0"}
  until [ "${_seq}" -ge "${_max}" ]; do
    local _peer="peer-${_seq}"
    _seq=$((${_seq}+1))
    ${sumd} -p ${DATA_ROOT}/cli/crypto/${_peer}
    ${sucp} -R ${DATA_ROOT}/peers/${_peer}/crypto/tls ${DATA_ROOT}/cli/crypto/${_peer}
  done

  local _admin=${ADMIN_USER:-"Admin"}
  ${sumd} -p ${DATA_ROOT}/cli/crypto/${_admin}\@${FABRIC_ORG}
  ${sucp} -R ${DATA_ROOT}/crypto/users/${_admin}\@${FABRIC_ORG}/msp ${DATA_ROOT}/cli/crypto/${_admin}\@${FABRIC_ORG}
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
  local _seq=${ORDERER_MIN:-"0"}
  local _max=${ORDERER_MAX:-"0"}
  until [ "${_seq}" -ge "${_max}" ]; do
    local _orderer="orderer-${_seq}"
    _seq=$((${_seq}+1))
    echo "cleanup crypto of ${_orderer}"
    ${surm} -R ${DATA_ROOT}/orderers/${_orderer}/crypto
  done

  # cleanup crypto of peers
  _seq=${PEER_MIN:-"0"}
  _max=${PEER_MAX:-"0"}
  until [ "${_seq}" -ge "${_max}" ]; do
    local _peer="peer-${_seq}"
    _seq=$((${_seq}+1))
    echo "cleanup crypto of ${_peer}"
    ${surm} -R ${DATA_ROOT}/peers/${_peer}/crypto
  done
}

# cleanup old crypto and collect all new crypto for bootstrap nodes and users
function collectAllCrypto {
  # cleanup all old crypto for bootstrap
  cleanupCrypto

  # copy CA
  copyCACrypto ca
  copyCACrypto tlsca
  printConfigYaml | ${stee} ${DATA_ROOT}/crypto/msp/config.yaml > /dev/null

  # copy nodes
  copyOrdererCrypto
  copyPeerCrypto
  
  # copy users
  copyNodeCrypto ${ADMIN_USER:-"Admin"} users server
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

function verifyRequest {
  case "${CMD}" in
  orderer)
    if [ -z "${START_SEQ}" ]; then
      echo "no sequence number specified for adding orderers"
      printHelp
      exit 1
    fi
    ;;
  peer)
    if [ -z "${START_SEQ}" ]; then
      echo "no sequence number specified for adding peers"
      printHelp
      exit 1
    fi
    ;;
  admin)
    if [ -z "${NEW_USERS}" ]; then
      echo "no user name specified for adding admin users"
      printHelp
      exit 1
    fi
    ;;
  user)
    if [ -z "${NEW_USERS}" ]; then
      echo "no user name specified for adding client users"
      printHelp
      exit 1
    fi
    ;;
  esac
}

# Print the usage message
function printHelp {
  echo "Usage: "
  echo "  ca-crypto.sh <cmd> [-p <property file>] [-t <env type>] [-s <start seq>] [-e <end seq>] [-u <user name>]"
  echo "    <cmd> - one of 'bootstrap', 'orderer', 'peer', 'admin', or 'user'"
  echo "      - 'bootstrap' - generate crypto for all orderers, peers, and users in a network spec"
  echo "      - 'orderer' - generate crypto for specified orderers"
  echo "      - 'peer' - generate crypto for specified peers"
  echo "      - 'admin' - generate crypto for specified admin users"
  echo "      - 'user' - generate crypto for specified client users"
  echo "    -p <property file> - the .env file in config folder that defines network properties, e.g., netop1 (default)"
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', or 'az'"
  echo "    -s <start seq> - start sequence number (inclusive) for orderer or peer"
  echo "    -e <end seq> - end sequence number (exclusive) for orderer or peer"
  echo "    -u <user name> - space-delimited admin/client user names"
  echo "  ca-crypto.sh -h (print this message)"
}

ORG_ENV="netop1"
ENV_TYPE="k8s"

CMD=${1}
shift
while getopts "h?p:t:s:e:u:" opt; do
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
  s)
    START_SEQ=$OPTARG
    ;;
  e)
    END_SEQ=$OPTARG
    ;;
  u)
    NEW_USERS=$OPTARG
    ;;
  esac
done
verifyRequest

source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORG_ENV} ${ENV_TYPE}
ORG=${FABRIC_ORG%%.*}
ORG_DIR=${DATA_ROOT}/canet

case "${CMD}" in
bootstrap)
  echo "bootstrap ${ORG_ENV} ${ENV_TYPE}"
  genCrypto
  collectAllCrypto
  ;;
orderer)
  echo "add orderer [ ${START_SEQ} ${END_SEQ} ]"
  genCrypto ${CMD} ${START_SEQ} ${END_SEQ}
  copyOrdererCrypto ${START_SEQ} ${END_SEQ}
  ;;
peer)
  echo "add peer [ ${START_SEQ} ${END_SEQ} ]"
  genCrypto ${CMD} ${START_SEQ} ${END_SEQ}
  copyPeerCrypto ${START_SEQ} ${END_SEQ}
  ;;
admin)
  echo "add admin user [ ${NEW_USERS} ]"
  genCrypto ${CMD} ${NEW_USERS}
  for u in ${NEW_USERS}; do
    copyNodeCrypto ${u} users server
  done
  ;;
user)
  echo "add client user [ ${NEW_USERS} ]"
  genCrypto ${CMD} ${NEW_USERS}
  for u in ${NEW_USERS}; do
    copyNodeCrypto ${u} users client
  done
  ;;
*)
  printHelp
  exit 1
esac
