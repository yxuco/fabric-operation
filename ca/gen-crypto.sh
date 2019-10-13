#!/bin/bash
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

ADMIN=${ADMIN_USER:-"Admin"}
ADMINPW=${ADMIN_PASSWD:-"adminpw"}
CSR_HOSTS=${CLIENT_HOSTS:-"localhost,cli.${FABRIC_ORG}"}

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

# genCrypto ca|tlsca
# e.g., genCrypto ca
function genCrypto {
  CA_NAME=${1}
  PORT=7054
  if [ "${CA_NAME}" == "ca" ]; then
    export FABRIC_CA_CLIENT_HOME=${FABRIC_CA_HOME}/caadmin
    USER=${CA_ADMIN}
    PASSWD=${CA_PASSWD}
    PROFILE=""
    CRYPTO_DIR="msp"
  else
    export FABRIC_CA_CLIENT_HOME=${FABRIC_CA_HOME}/tlsadmin
    USER=${TLS_ADMIN}
    PASSWD=${TLS_PASSWD}
    PROFILE="--enrollment.profile tls"
    CRYPTO_DIR="tls"
  fi

  # enroll CA admin for client
  fabric-ca-client getcainfo --tls.certfiles tls-cert.pem -u https://${CA_NAME}.${FABRIC_ORG}:${PORT}
  fabric-ca-client enroll --tls.certfiles tls-cert.pem --csr.names "${CSR_NAMES}" --csr.hosts "caclient.${FABRIC_ORG},localhost" -u https://${USER}:${PASSWD}@${CA_NAME}.${FABRIC_ORG}:${PORT}

  # register admin user
  echo "register ${ADMIN}@${FABRIC_ORG}"
  fabric-ca-client register --id.name ''"${ADMIN}@${FABRIC_ORG}"'' --id.secret ${ADMINPW} --id.type admin --tls.certfiles tls-cert.pem -u https://${USER}:${PASSWD}@${CA_NAME}.${FABRIC_ORG}:${PORT}

  # register users
  if [ ! -z "${USERS}" ]; then
    for u in ${USERS}; do
      echo "register ${u}@${FABRIC_ORG}"
      fabric-ca-client register --id.name ''"${u}@${FABRIC_ORG}"'' --id.secret ${u}pw --id.type client --id.attrs 'alias='"${u}"',email='"${u}@${FABRIC_ORG}"'' --tls.certfiles tls-cert.pem -u https://${USER}:${PASSWD}@${CA_NAME}.${FABRIC_ORG}:${PORT}
    done
  fi

  # register orderers
  for ord in "${ORDERERS[@]}"; do
    echo "register ${ord}"
    fabric-ca-client register --id.name ${ord}.${FABRIC_ORG} --id.secret ${ord}pw --id.type orderer --tls.certfiles tls-cert.pem -u https://${USER}:${PASSWD}@${CA_NAME}.${FABRIC_ORG}:${PORT}
  done

  # register peers
  for p in "${PEERS[@]}"; do
    echo "register ${p}"
    fabric-ca-client register --id.name ${p}.${FABRIC_ORG} --id.secret ${p}pw --id.type peer --tls.certfiles tls-cert.pem -u https://${USER}:${PASSWD}@${CA_NAME}.${FABRIC_ORG}:${PORT}
  done

  # enroll admin user
  echo "enroll ${ADMIN}@${FABRIC_ORG}"
  fabric-ca-client enroll --tls.certfiles tls-cert.pem ${PROFILE} --csr.names "${CSR_NAMES}" --csr.hosts "${CSR_HOSTS}" -u https://${ADMIN}@${FABRIC_ORG}:${ADMINPW}@${CA_NAME}.${FABRIC_ORG}:${PORT} -M ${FABRIC_CA_HOME}/${ADMIN}\@${FABRIC_ORG}/${CRYPTO_DIR}

  # enroll users
  if [ ! -z "${USERS}" ]; then
    for u in ${USERS}; do
      echo "enroll ${u}@${FABRIC_ORG}"
      fabric-ca-client enroll --tls.certfiles tls-cert.pem ${PROFILE} --csr.names "${CSR_NAMES}" --csr.hosts "${CSR_HOSTS}" --enrollment.attrs "alias,email,hf.Type,hf.EnrollmentID" -u https://${u}@${FABRIC_ORG}:${u}pw@${CA_NAME}.${FABRIC_ORG}:${PORT} -M ${FABRIC_CA_HOME}/${u}\@${FABRIC_ORG}/${CRYPTO_DIR}
    done
  fi

  # enroll orderers
  for ord in "${ORDERERS[@]}"; do
    echo "enroll ${ord}"
    fabric-ca-client enroll --tls.certfiles tls-cert.pem ${PROFILE} --csr.names "${CSR_NAMES}" --csr.hosts "${ord}.${FABRIC_ORG},${ord},localhost" -u https://${ord}.${FABRIC_ORG}:${ord}pw@${CA_NAME}.${FABRIC_ORG}:${PORT} -M ${FABRIC_CA_HOME}/${ord}/${CRYPTO_DIR}
  done

  # enroll peers
  for p in "${PEERS[@]}"; do
    echo "enroll ${p}"
    fabric-ca-client enroll --tls.certfiles tls-cert.pem ${PROFILE} --csr.names "${CSR_NAMES}" --csr.hosts "${p}.${FABRIC_ORG},${p},localhost" -u https://${p}.${FABRIC_ORG}:${p}pw@${CA_NAME}.${FABRIC_ORG}:${PORT} -M ${FABRIC_CA_HOME}/${p}/${CRYPTO_DIR}
  done
}

function main {
  getOrderers
  getPeers
  genCrypto ca
  genCrypto tlsca
}

main