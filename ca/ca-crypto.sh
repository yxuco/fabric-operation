#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# generate crypto keys using CA server of a specified org, and ca server env, i.e., docker or k8s
# ca-crypto.sh <cmd> [-p <property file>] [-t <env type>] [-s <start seq>] [-e <end seq>] [-u <user name>]
# where property file for the org are specified in ../config/org_name.env, e.g.
#   ca-crypto.sh bootstrap -p netop1
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"

# genCrypto <args>
# args are passed to gen-crypto.sh for ca-client
function genCrypto {
  ${sumd} -p ${DATA_ROOT}/canet/ca-client/caadmin
  ${sumd} -p ${DATA_ROOT}/canet/ca-client/tlsadmin

  ${sucp} $(dirname "${SCRIPT_DIR}")/config/${ORG_ENV}.env ${DATA_ROOT}/canet/ca-client/org.env
  ${sucp} ${SCRIPT_DIR}/gen-crypto.sh ${DATA_ROOT}/canet/ca-client
  ${sucp} ${DATA_ROOT}/canet/ca-server/tls-cert.pem ${DATA_ROOT}/canet/ca-client/caadmin
  ${sucp} ${DATA_ROOT}/canet/tlsca-server/tls-cert.pem ${DATA_ROOT}/canet/ca-client/tlsadmin

  # generate crypto data
  local _cmd="gen-crypto.sh $@"
  if [ "${ENV_TYPE}" == "docker" ]; then
    echo "use docker-compose - ${_cmd}"
    docker exec -it caclient.${FABRIC_ORG} bash -c "./${_cmd}"
  else
    echo "use k8s - ${_cmd}"
    cpod=$(kubectl get pod -l app=ca-client -o name -n ${ORG})
    if [ -z "${cpod}" ]; then
      echo "Error: ca-client is not running, start ca server and client first"
      exit 1
    else
      echo "generate crypto using ca-client: ${cpod##*/}"
      kubectl exec -it ${cpod##*/} -n ${ORG} -- bash -c "./${_cmd}"
    fi
  fi
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
  echo "    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', 'az', or 'gcp'"
  echo "    -s <start seq> - start sequence number (inclusive) for orderer or peer"
  echo "    -e <end seq> - end sequence number (exclusive) for orderer or peer"
  echo "    -u <user name> - space-delimited admin/client user names"
  echo "  ca-crypto.sh -h (print this message)"
}

ORG_ENV="netop1"

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

case "${CMD}" in
bootstrap)
  echo "bootstrap ${ORG_ENV} ${ENV_TYPE}"
  genCrypto ${CMD}
  ;;
orderer)
  echo "add orderer [ ${START_SEQ} ${END_SEQ} ]"
  genCrypto ${CMD} ${START_SEQ} ${END_SEQ}
  ;;
peer)
  echo "add peer [ ${START_SEQ} ${END_SEQ} ]"
  genCrypto ${CMD} ${START_SEQ} ${END_SEQ}
  ;;
admin)
  echo "add admin user [ ${NEW_USERS} ]"
  genCrypto ${CMD} ${NEW_USERS}
  ;;
user)
  echo "add client user [ ${NEW_USERS} ]"
  genCrypto ${CMD} ${NEW_USERS}
  ;;
*)
  printHelp
  exit 1
esac
