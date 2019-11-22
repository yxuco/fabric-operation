#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# Run this sript in tool container to generate network artifacts
# usage: gen-artifact.sh <cmd> <args>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"

function bootstrap {
  createGenesisBlock ${ORDERER_TYPE}
  createChannelTx ${TEST_CHANNEL}
}

function createGenesisBlock {
  if [ "$1" == "solo" ] || [ "$1" == "etcdraft" ]; then
    check=$(grep "${1}OrdererGenesis:" configtx.yaml)
    if [ -z "${check}" ]; then
      echo "profile ${1}OrdererGenesis is not defiled"
    else
      configtxgen -profile ${1}OrdererGenesis -channelID ${SYS_CHANNEL} -outputBlock ./${1}-genesis.block
    fi
  else
    echo "'$1' is not a supported orderer type. choose 'solo' or 'etcdraft'"
  fi
}

function createChannelTx {
  check=$(grep "${ORG}Channel:" configtx.yaml)
  if [ -z "${check}" ]; then
    echo "profile ${ORG}Channel is not defined"
  else
    configtxgen -profile ${ORG}Channel -outputCreateChannelTx ./${1}.tx -channelID ${1}
    configtxgen -profile ${ORG}Channel -outputAnchorPeersUpdate ./${1}-anchors.tx -channelID ${1} -asOrg ${ORG_MSP}
  fi
}

function anchorConfig {
  local anchor="peer-0.${FABRIC_ORG}"
  if [ ! -z "${SVC_DOMAIN}" ]; then
    anchor="peer-0.peer.${SVC_DOMAIN}"
  fi

  echo "{
	\"values\": {
    \"AnchorPeers\": {
      \"mod_policy\": \"Admins\",
      \"value\": {
        \"anchor_peers\": [
          {
            \"host\": \"${anchor}\",
            \"port\": 7051
          }
        ]
      },
      \"version\": \"0\"
    }
  }
}"
}

function createPeerMspConfig {
  configtxgen -printOrg ${ORG_MSP} > mspConfig.json
  anchorConfig > anchorConfig.json
  jq -s '.[0] * .[1]' mspConfig.json anchorConfig.json > ${ORG_MSP}.json
  echo "created peer MSP config file: ${ORG_MSP}.json"
}

# printOrdererConfig <start-seq> <end-seq>
function printOrdererConfig {
  echo "{
  \"consenters\": ["

  local seq=${1:-"0"}
  local max=${2:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    local orderer="orderer-${seq}"
    seq=$((${seq}+1))
    echo "    {"
    printConcenterConfig ${orderer}
    if [ "${seq}" -eq "${max}" ]; then
      echo "    }"
    else
      echo "    },"
    fi
  done
  echo "  ],
  \"addresses\": ["
  local seq=${1:-"0"}
  local max=${2:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    local orderer="orderer-${seq}"
    seq=$((${seq}+1))
    if [ "${seq}" -eq "${max}" ]; then
      echo "    \"${orderer}.orderer.${SVC_DOMAIN}:7050\""
    else
      echo "    \"${orderer}.orderer.${SVC_DOMAIN}:7050\","
    fi
  done
  echo "  ]
}"
}

# printConcenterConfig <orderer>
function printConcenterConfig {
  local o_cert=./crypto/orderers/${1}/tls/server.crt
  if [ ! -f "${o_cert}" ]; then
    return 1
  else
    local crt=$(cat ${o_cert} | base64 -w 0)
    echo "      \"client_tls_cert\": \"${crt}\",
      \"host\": \"${1}.orderer.${SVC_DOMAIN}\",
      \"port\": 7050,
      \"server_tls_cert\": \"${crt}\""
  fi
}

# Print the usage message
function printUsage {
  echo "Usage: "
  echo "  gen-artifact.sh <cmd> <args>"
  echo "    <cmd> - one of 'bootstrap', 'genesis', or 'channel'"
  echo "      - 'bootstrap' (default) - generate genesis block and test-channel tx as specified by container env"
  echo "      - 'mspconfig' - print peer MSP config json for adding to a network"
  echo "      - 'orderer-config' - print orderer RAFT consenter config, <args> = <start-seq> [<end-seq>]"
  echo "      - 'genesis' - generate genesis block for specified orderer type, <args> = <orderer type>"
  echo "      - 'channel' - generate tx for create and anchor of a channel, <args> = <channel name>"
}

CMD=${1:-"bootstrap"}
shift
ARGS="$@"

case "${CMD}" in
bootstrap)
  echo "bootstrap ${ORDERER_TYPE} genesis block and tx for test channel ${TEST_CHANNEL}"
  bootstrap
  ;;
mspconfig)
  echo "print peer MSP config '${ORG_MSP}.json' used to add it to a network"
  createPeerMspConfig
  ;;
orderer-config)
  echo "print orderer RAFT consenter config [${1}, ${2}), used to add it to a network"
  printOrdererConfig ${ARGS} > ordererConfig-${1}.json
  echo "created RAFT consenter config: ordererConfig-${1}.json"
  ;;
genesis)
  if [ -z "${ARGS}" ]; then
    echo "orderer type not specified for genesis block"
    printUsage
    exit 1
  else
    echo "create genesis block for orderer type [ ${ARGS} ]"
    createGenesisBlock ${ARGS}
  fi
  ;;
channel)
  if [ -z "${ARGS}" ]; then
    echo "channel name not specified for tx"
    printUsage
    exit 1
  else
    echo "create tx for test channel [ ${ARGS} ]"
    createChannelTx ${ARGS}
  fi
  ;;
*)
  printUsage
  exit 1
esac