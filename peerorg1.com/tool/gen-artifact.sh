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

function createMspConfig {
  configtxgen -printOrg ${ORG_MSP} > mspConfig.json
  anchorConfig > anchorConfig.json
  jq -s '.[0] * .[1]' mspConfig.json anchorConfig.json > ${ORG_MSP}.json
  echo "created MSP config file: ${ORG_MSP}.json"
}

# Print the usage message
function printUsage {
  echo "Usage: "
  echo "  gen-artifact.sh <cmd> <args>"
  echo "    <cmd> - one of 'bootstrap', 'genesis', or 'channel'"
  echo "      - 'bootstrap' (default) - generate genesis block and test-channel tx as specified by container env"
  echo "      - 'mspconfig' - print MSP config json for adding to a network"
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
  echo "print config '${ORG_MSP}.json' used to add it to a network"
  createMspConfig
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