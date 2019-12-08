#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# Run this sript in ca-client container to generate crypto cert and keys for orderers and peers of an org
# usage: gen-crypto.sh
# it reads config parameters for the org from file ./org.env in the same same script folder.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source ${SCRIPT_DIR}/org.env
ORG=${FABRIC_ORG%%.*}
COUNTRY=${CSR_COUNTRY:-"US"}
STATE=${CSR_STATE:-"Colorado"}
CITY=${CSR_CITY:-"Denver"}
CSR_NAMES="C=${COUNTRY},ST=${STATE},L=${CITY},O=${FABRIC_ORG}"

# print out the host:port for a specified ca-server name
# Usage: caHostPort ca|tls
function caHostPort {
  # SVC_DOMAIN is set in k8s client pod yaml, indicating that k8s is in use
  if [ ! -z "${SVC_DOMAIN}" ]; then
    if [ "${1}" == "ca" ]; then
      echo "ca-server.${SVC_DOMAIN}:${CA_PORT:-"7054"}"
    else
      echo "tlsca-server.${SVC_DOMAIN}:${TLS_PORT:-"7055"}"
    fi
  else
    # use host:port for docker-compose
    echo "${1}.${FABRIC_ORG}:7054"
  fi
}

# print out https://user:pass@host:port for ca admin user
# Usage: caAdminUrl ca|tls
function caAdminUrl {
  local _hostPort=$(caHostPort ${1})
  if [ "${1}" == "ca" ]; then
    local _admUser=${CA_ADMIN:-"caadmin"}
    local _admPass=${CA_PASSWD:-"caadminpw"}
    echo "https://${_admUser}:${_admPass}@${_hostPort}"
  else
    local _admUser=${TLS_ADMIN:-"tlsadmin"}
    local _admPass=${TLS_PASSWD:-"tlsadminpw"}
    echo "https://${_admUser}:${_admPass}@${_hostPort}"
  fi
}

# adminCrypto register|enroll [ adm-1 adm-2 ]
function adminCrypto {
  local _cmd=$1
  shift
  local _csrhosts=${CLIENT_HOSTS:-"localhost,cli.${FABRIC_ORG}"}
  if [ "$#" -eq 0 ]; then
    # no admin user specified, so bootstrap the admin user defined in network spec
    local _admin=${ADMIN_USER:-"Admin"}
    local _pass=${ADMIN_PASSWD:-"adminpw"}
    if [ "${_cmd}" == "enroll" ]; then
      echo "enroll ${_admin}@${FABRIC_ORG} - ${CRYPTO_DIR}"
      fabric-ca-client enroll --tls.certfiles tls-cert.pem ${PROFILE} --csr.names "${CSR_NAMES}" --csr.hosts "${_csrhosts}" -u https://${_admin}@${FABRIC_ORG}:${_pass}@${CA_HOST_PORT} -M ${FABRIC_CA_HOME}/${_admin}\@${FABRIC_ORG}/${CRYPTO_DIR}
      if [ "${CRYPTO_DIR}" == "tls" ]; then
        # assuming "tlsca" is called after "ca"
        copyNodeCrypto ${_admin} users server
      fi
    else
      echo "register ${_admin}@${FABRIC_ORG} - ${CRYPTO_DIR}"
      fabric-ca-client register --id.name ''"${_admin}@${FABRIC_ORG}"'' --id.secret ${_pass} --id.type admin --tls.certfiles tls-cert.pem -u ${CA_ADMIN_URL}
    fi
  else
    if [ "${_cmd}" == "enroll" ]; then
      for u in "$@"; do
        echo "enroll ${u}@${FABRIC_ORG} - ${CRYPTO_DIR}"
        fabric-ca-client enroll --tls.certfiles tls-cert.pem ${PROFILE} --csr.names "${CSR_NAMES}" --csr.hosts "${_csrhosts}" -u https://${u}@${FABRIC_ORG}:${u}pw@${CA_HOST_PORT} -M ${FABRIC_CA_HOME}/${u}\@${FABRIC_ORG}/${CRYPTO_DIR}
        if [ "${CRYPTO_DIR}" == "tls" ]; then
          # assuming "tlsca" is called after "ca"
          copyNodeCrypto ${u} users server
        fi
      done
    else
      for u in "$@"; do
        echo "register ${u}@${FABRIC_ORG} - ${CRYPTO_DIR}"
        fabric-ca-client register --id.name ''"${u}@${FABRIC_ORG}"'' --id.secret ${u}pw --id.type admin --tls.certfiles tls-cert.pem -u ${CA_ADMIN_URL}
      done
    fi
  fi
}

# userCrypto register|enroll [ user-1 user-2 ]
function userCrypto {
  local _cmd=$1
  shift
  local _users="$@"
  if [ -z "${_users}" ]; then
    # no users specified, so bootstrap all users defined in network spec
    if [ ! -z "${USERS}" ]; then
      _users="${USERS}"
    fi
  fi
  if [ ! -z "${_users}" ]; then
    if [ "${_cmd}" == "enroll" ]; then
      local _csrhosts=${CLIENT_HOSTS:-"localhost,cli.${FABRIC_ORG}"}
      for u in ${_users}; do
        echo "enroll ${u}@${FABRIC_ORG} - ${CRYPTO_DIR}"
        fabric-ca-client enroll --tls.certfiles tls-cert.pem ${PROFILE} --csr.names "${CSR_NAMES}" --csr.hosts "${_csrhosts}" --enrollment.attrs "alias,email,hf.Type,hf.EnrollmentID" -u https://${u}@${FABRIC_ORG}:${u}pw@${CA_HOST_PORT} -M ${FABRIC_CA_HOME}/${u}\@${FABRIC_ORG}/${CRYPTO_DIR}
        if [ "${CRYPTO_DIR}" == "tls" ]; then
          # assuming "tlsca" is called after "ca"
          copyNodeCrypto ${u} users client
        fi
      done
    else
      for u in ${_users}; do
        echo "register ${u}@${FABRIC_ORG} - ${CRYPTO_DIR}"
        fabric-ca-client register --id.name ''"${u}@${FABRIC_ORG}"'' --id.secret ${u}pw --id.type client --id.attrs 'alias='"${u}"',email='"${u}@${FABRIC_ORG}"'' --tls.certfiles tls-cert.pem -u ${CA_ADMIN_URL}
      done
    fi
  fi
}

# ordererCrypto register|enroll [ 1 2 ]
function ordererCrypto {
  local _cmd=$1
  shift
  local _seq=$1
  local _max=$2

  if [ -z "${_seq}" ]; then
    # no orderer specified, so bootstrap all orderers defined in network spec
    _seq=${ORDERER_MIN:-"0"}
    _max=${ORDERER_MAX:-"0"}
  elif [ -z "${_max}" ]; then
    # create only 1 orderer if max seq is not specified
    _max=$((${_seq}+1))
  fi

  until [ "${_seq}" -ge "${_max}" ]; do
    local _orderer="orderer-${_seq}"
    _seq=$((${_seq}+1))

    if [ "${_cmd}" == "enroll" ]; then
      echo "enroll ${_orderer} - ${CRYPTO_DIR}"
      local o_hosts="${_orderer}.${FABRIC_ORG},${_orderer},localhost"
      if [ ! -z "${SVC_DOMAIN}" ]; then
        o_hosts="${_orderer}.orderer.${SVC_DOMAIN},${o_hosts}"
      fi
      fabric-ca-client enroll --tls.certfiles tls-cert.pem ${PROFILE} --csr.names "${CSR_NAMES}" --csr.hosts "${o_hosts}" -u https://${_orderer}.${FABRIC_ORG}:${_orderer}pw@${CA_HOST_PORT} -M ${FABRIC_CA_HOME}/${_orderer}/${CRYPTO_DIR}
      if [ "${CRYPTO_DIR}" == "tls" ]; then
        # assuming "tlsca" is called after "ca"
        copyNodeCrypto ${_orderer} orderers server
      fi
    else
      echo "register ${_orderer} - ${CRYPTO_DIR}"
      fabric-ca-client register --id.name ${_orderer}.${FABRIC_ORG} --id.secret ${_orderer}pw --id.type orderer --tls.certfiles tls-cert.pem -u ${CA_ADMIN_URL}
    fi
  done
}

# peerCrypto register|enroll [ 1 2 ]
function peerCrypto {
  local _cmd=$1
  shift
  local _seq=$1
  local _max=$2

  if [ -z "${_seq}" ]; then
    # no peer specified, so bootstrap all peers defined in network spec
    _seq=${PEER_MIN:-"0"}
    _max=${PEER_MAX:-"0"}
  elif [ -z "${_max}" ]; then
    # create only 1 peer if max seq is not specified
    _max=$((${_seq}+1))
  fi

  until [ "${_seq}" -ge "${_max}" ]; do
    local _peer="peer-${_seq}"
    _seq=$((${_seq}+1))

    if [ "${_cmd}" == "enroll" ]; then
      echo "enroll ${_peer} - ${CRYPTO_DIR}"
      local p_hosts="${_peer}.${FABRIC_ORG},${_peer},localhost"
      if [ ! -z "${SVC_DOMAIN}" ]; then
        p_hosts="${_peer}.peer.${SVC_DOMAIN},${p_hosts}"
      fi
      fabric-ca-client enroll --tls.certfiles tls-cert.pem ${PROFILE} --csr.names "${CSR_NAMES}" --csr.hosts "${p_hosts}" -u https://${_peer}.${FABRIC_ORG}:${_peer}pw@${CA_HOST_PORT} -M ${FABRIC_CA_HOME}/${_peer}/${CRYPTO_DIR}
      if [ "${CRYPTO_DIR}" == "tls" ]; then
        # assuming "tlsca" is called after "ca"
        copyNodeCrypto ${_peer} peers server
      fi
    else
      echo "register ${_peer} - ${CRYPTO_DIR}"
      fabric-ca-client register --id.name ${_peer}.${FABRIC_ORG} --id.secret ${_peer}pw --id.type peer --tls.certfiles tls-cert.pem -u ${CA_ADMIN_URL}
    fi
  done
}

# genCrypto ca|tlsca
# e.g., genCrypto ca
function genCrypto {
  CA_HOST_PORT=$(caHostPort ${1})
  CA_ADMIN_URL=$(caAdminUrl ${1})
  echo "CA admin URL: ${CA_ADMIN_URL}"

  if [ "${1}" == "ca" ]; then
    export FABRIC_CA_CLIENT_HOME=${FABRIC_CA_HOME}/caadmin
    PROFILE=""
    CRYPTO_DIR="msp"
  else
    export FABRIC_CA_CLIENT_HOME=${FABRIC_CA_HOME}/tlsadmin
    PROFILE="--enrollment.profile tls"
    CRYPTO_DIR="tls"
  fi

  # enroll CA admin for client
  fabric-ca-client getcainfo --tls.certfiles tls-cert.pem -u https://${CA_HOST_PORT}
  fabric-ca-client enroll --tls.certfiles tls-cert.pem --csr.names "${CSR_NAMES}" --csr.hosts "caclient.${FABRIC_ORG},localhost" -u ${CA_ADMIN_URL}

  # register users and nodes
  if [ "${CMD}" == "admin" ]; then
    echo "register new admins [ ${ARGS} ]"
    adminCrypto register ${ARGS}
  elif [ "${CMD}" == "user" ]; then
    echo "register new users [ ${ARGS} ]"
    userCrypto register ${ARGS}
  elif [ "${CMD}" == "orderer" ]; then
    echo "register orderers [ ${ARGS} ]"
    ordererCrypto register ${ARGS}
  elif [ "${CMD}" == "peer" ]; then
    echo "register peers [ ${ARGS} ]"
    peerCrypto register ${ARGS}
  else
    echo "bootstrap regisger"
    adminCrypto register
    userCrypto register
    ordererCrypto register
    peerCrypto register
  fi

  # enroll users and nodes
  if [ "${CMD}" == "admin" ]; then
    echo "enroll new admins [ ${ARGS} ]"
    adminCrypto enroll ${ARGS}
  elif [ "${CMD}" == "user" ]; then
    echo "enroll new users [ ${ARGS} ]"
    userCrypto enroll ${ARGS}
  elif [ "${CMD}" == "orderer" ]; then
    echo "enroll orderers [ ${ARGS} ]"
    ordererCrypto enroll ${ARGS}
  elif [ "${CMD}" == "peer" ]; then
    echo "enroll peers [ ${ARGS} ]"
    peerCrypto enroll ${ARGS}
  else
    echo "bootstrap enroll"
    adminCrypto enroll
    userCrypto enroll
    ordererCrypto enroll
    peerCrypto enroll
  fi
}

###############################################################################
# copy crypto to sharable directory structure
###############################################################################

# cleanup crypto of msp, users and bootstrap orderers and peers
function cleanupCrypto {
  # cleanup target MSP folder
  for f in ca tlsca msp users; do
    echo "cleanup ${f}"
    rm -R ${DATA_ROOT}/crypto/${f}
  done

  # cleanup tool and cli crypto folders
  for f in tool cli; do
    echo "cleanup ${f} crypto"
    rm -R ${DATA_ROOT}/${f}/crypto
  done
  echo "cleanup gateway crypto"
  rm -R ${DATA_ROOT}/gateway/${FABRIC_ORG}

  # cleanup crypto of orderers
  local _seq=${ORDERER_MIN:-"0"}
  local _max=${ORDERER_MAX:-"0"}
  until [ "${_seq}" -ge "${_max}" ]; do
    local _orderer="orderer-${_seq}"
    _seq=$((${_seq}+1))
    echo "cleanup crypto of ${_orderer}"
    rm -R ${DATA_ROOT}/orderers/${_orderer}/crypto
  done

  # cleanup crypto of peers
  _seq=${PEER_MIN:-"0"}
  _max=${PEER_MAX:-"0"}
  until [ "${_seq}" -ge "${_max}" ]; do
    local _peer="peer-${_seq}"
    _seq=$((${_seq}+1))
    echo "cleanup crypto of ${_peer}"
    rm -R ${DATA_ROOT}/peers/${_peer}/crypto
  done
}

# create msp and ca crypto if they do not already exist
function initCrypto {
  if [ ! -f "${DATA_ROOT}/crypto/msp/config.yaml" ]; then
    echo "copy ca and msp crypto"
    copyCACrypto ca
    copyCACrypto tlsca
    printConfigYaml > ${DATA_ROOT}/crypto/msp/config.yaml

    # initialize tool crypto
    mkdir -p ${DATA_ROOT}/tool/crypto
    cp -R ${DATA_ROOT}/crypto/msp ${DATA_ROOT}/tool/crypto

    # initialize cli crypto if the org provides orderers
    if [ "${ORDERER_MAX:-"0"}" -gt 0 ]; then
      mkdir -p ${DATA_ROOT}/cli/crypto/orderer-0/msp
      cp -R ${DATA_ROOT}/crypto/msp/tlscacerts ${DATA_ROOT}/cli/crypto/orderer-0/msp
    fi

    # initialize gateway crypto
    mkdir -p ${DATA_ROOT}/gateway/${FABRIC_ORG}/ca/tls
    cp ${DATA_ROOT}/crypto/ca/tls/server.crt ${DATA_ROOT}/gateway/${FABRIC_ORG}/ca/tls
    cp -R ${DATA_ROOT}/crypto/msp/tlscacerts ${DATA_ROOT}/gateway/${FABRIC_ORG}
  else
    echo "${DATA_ROOT}/crypto/msp/config.yaml already exists"
  fi
}

# copyCACrypto ca|tlsca
function copyCACrypto {
  echo "copy crypto for ${1}"
  local _ca=${1}
  local _target=${DATA_ROOT}/crypto/${_ca}
  mkdir -p ${_target}/tls

  local _src=${DATA_ROOT}/canet/${_ca}-server
  cp ${_src}/ca-cert.pem ${_target}/${_ca}.${FABRIC_ORG}-cert.pem
  cp ${_src}/tls-cert.pem ${_target}/tls/server.crt
  mkdir -p ${DATA_ROOT}/crypto/msp/${_ca}certs
  cp ${_src}/ca-cert.pem ${DATA_ROOT}/crypto/msp/${_ca}certs/${_ca}.${FABRIC_ORG}-cert.pem

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
  for f in ${_src}/msp/keystore/*_sk; do
    echo ${f}
    sum=$(openssl pkey -in ${f} -pubout -outform pem | ${CHECKSUM})
    echo "checksum from private key: ${sum}"
    if [ "${sum}" == "${pubsum}" ]; then
      cp ${f} ${_target}/${_ca}.${FABRIC_ORG}-key.pem
      echo "Got CA private key: ${f}"
    elif [ "${sum}" == "${tlssum}" ]; then
      cp ${f} ${_target}/tls/server.key
      echo "Got CA TLS private key: ${f}"
    fi
  done
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

# copyNodeCrypto <node-namme> peers|orderers|users client|server
# e.g., copyNodeCrypto peer-1 peers server
function copyNodeCrypto {
  echo "copy crypto for ${1}"
  local _name=${1}.${FABRIC_ORG}
  local _src=${DATA_ROOT}/canet/ca-client/${1}
  local _target=${DATA_ROOT}/${2}/${1}/crypto
  if [ "${2}" == "users" ]; then
    _name=${1}\@${FABRIC_ORG}
    _src=${DATA_ROOT}/canet/ca-client/${_name}
    _target=${DATA_ROOT}/crypto/${2}/${_name}
  fi

  # copy msp data
  mkdir -p ${_target}/msp
  cp -R ${DATA_ROOT}/crypto/msp/cacerts ${_target}/msp
  cp -R ${DATA_ROOT}/crypto/msp/tlscacerts ${_target}/msp
  cp -R ${_src}/msp/signcerts ${_target}/msp
  cp -R ${_src}/msp/keystore ${_target}/msp
  cp ${DATA_ROOT}/crypto/msp/config.yaml ${_target}/msp
  mv ${_target}/msp/signcerts/cert.pem ${_target}/msp/signcerts/${_name}-cert.pem

  # copy tls data
  mkdir -p ${_target}/tls
  cp ${DATA_ROOT}/crypto/msp/tlscacerts/tlsca.${FABRIC_ORG}-cert.pem ${_target}/tls/ca.crt
  cp ${_src}/tls/signcerts/cert.pem ${_target}/tls/${3}.crt
  # there should be only one file, otherwise, take the last file
  for f in ${_src}/tls/keystore/*_sk; do
    cp ${f} ${_target}/tls/${3}.key
  done

  # copy orderer tls cert to tool crypto
  if [ "${2}" == "orderers" ]; then
    mkdir -p ${DATA_ROOT}/tool/crypto/orderers/${1}/tls
    cp ${_src}/tls/signcerts/cert.pem ${DATA_ROOT}/tool/crypto/orderers/${1}/tls/server.crt
  fi

  # copy peer tls key and cert to cli crypto
  if [ "${2}" == "peers" ]; then
    mkdir -p ${DATA_ROOT}/cli/crypto/${1}
    cp -R ${_target}/tls ${DATA_ROOT}/cli/crypto/${1}
  fi

  # copy user msp to cli and gateway crypto
  if [ "${2}" == "users" ]; then
    if [ "${3}" == "server" ]; then
      # copy admin user msp to cli crypto
      mkdir -p ${DATA_ROOT}/cli/crypto/${_name}
      cp -R ${_target}/msp ${DATA_ROOT}/cli/crypto/${_name}
    fi

    # copy all user msp to gateway crypto
    # Note that fabric-sdk-go requires the naming of folder and signcert file such that
    #  the crypto root folder ${FABRIC_ORG} must match the same ORG inserted in the filename under user's signcerts
    mkdir -p ${DATA_ROOT}/gateway/${FABRIC_ORG}/users/${_name}
    cp -R ${_target}/msp ${DATA_ROOT}/gateway/${FABRIC_ORG}/users/${_name}
  fi
}

# Print the usage message
function printUsage {
  echo "Usage: "
  echo "  gen-crypto.sh <cmd> <args>"
  echo "    <cmd> - one of 'bootstrap', 'orderer', 'peer', 'admin', or 'user'"
  echo "      - 'bootstrap' (default) - generate crypto for all orderers, peers, and users in a network spec"
  echo "      - 'orderer' - generate crypto for specified orderers, <args> = <start-seq> <end-seq>"
  echo "      - 'peer' - generate crypto for specified peers, <args> = <start-seq> <end-seq>"
  echo "      - 'admin' - generate crypto for specified admin users, <args> = space separated user names"
  echo "      - 'user' - generate crypto for specified client users, <args> = space separated user names"
}

function verifyRequest {
  case "${CMD}" in
  bootstrap)
    echo "bootstrap all crypto"
    ;;
  orderer)
    if [ -z "${ARGS}" ]; then
      echo "no sequence number specified for adding orderers"
      printUsage
      exit 1
    else
      echo "add orderers [ ${ARGS} ]"
    fi
    ;;
  peer)
    if [ -z "${ARGS}" ]; then
      echo "no sequence number specified for adding peers"
      printUsage
      exit 1
    else
      echo "add peers [ ${ARGS} ]"
    fi
    ;;
  admin)
    if [ -z "${ARGS}" ]; then
      echo "no user name specified for adding admin users"
      printUsage
      exit 1
    else
      echo "add admin users [ ${ARGS} ]"
    fi
    ;;
  user)
    if [ -z "${ARGS}" ]; then
      echo "no user name specified for adding client users"
      printUsage
      exit 1
    else
      echo "add client users [ ${ARGS} ]"
    fi
    ;;
  *)
    printUsage
    exit 1
  esac
}

CMD=${1:-"bootstrap"}
shift
ARGS="$@"
verifyRequest

if [ "${CMD}" == "bootstrap" ]; then
  cleanupCrypto
fi
initCrypto
genCrypto ca
genCrypto tlsca
