#!/bin/bash
# Run this sript in tool container to generate network artifacts
# usage: gen-artifact.sh <cmd> <args>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"

function bootstrap {
  createGenesisBlock ${ORDERER_TYPE}
  createChannelTx ${TEST_CHANNEL}
}

function createGenesisBlock {
  if [ "$1" == "solo" ] || [ "$1" == "etcdraft" ]; then
    configtxgen -profile ${1}OrdererGenesis -channelID ${SYS_CHANNEL} -outputBlock ./${1}-genesis.block
  else
    echo "'$1' is not a supported orderer type. choose 'solo' or 'etcdraft'"
  fi
}

function createChannelTx {
  configtxgen -profile ${ORG}Channel -outputCreateChannelTx ./${1}.tx -channelID ${1}
  configtxgen -profile ${ORG}Channel -outputAnchorPeersUpdate ./${1}-anchors.tx -channelID ${1} -asOrg ${ORG_MSP}
}

# Print the usage message
function printUsage {
  echo "Usage: "
  echo "  gen-artifact.sh <cmd> <args>"
  echo "    <cmd> - one of 'bootstrap', 'genesis', or 'channel'"
  echo "      - 'bootstrap' (default) - generate genesis block and test-channel tx as specified by container env"
  echo "      - 'genesis' - generate genesis block for specified orderer type, <args> = <orderer type>"
  echo "      - 'channel' - generate tx for create and anchor of a channel, <args> = <channel name>"
}

function handleRequest {
  case "${CMD}" in
  bootstrap)
    echo "bootstrap ${ORDERER_TYPE} genesis block and tx for test channel ${TEST_CHANNEL}"
    bootstrap
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
}

CMD=$1
if [ ! -z "${CMD}" ]; then
  shift
  ARGS="$@"
  handleRequest
else
  printUsage
fi
