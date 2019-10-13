#!/bin/bash
# Run this sript in cli container to generate orderer genesis block and tx for creating test channel
# usage: gen-config-block.sh

echo "Generate genesis block for orderer type ${ORDERER_TYPE} ..."
configtxgen -profile ${ORDERER_TYPE}OrdererGenesis -channelID ${SYS_CHANNEL} -outputBlock ./genesis.block

echo "Generate tx to create channel ${TEST_CHANNEL} for org ${ORG} ..."
configtxgen -profile ${ORG}Channel -outputCreateChannelTx ./channel.tx -channelID ${TEST_CHANNEL}
configtxgen -profile ${ORG}Channel -outputAnchorPeersUpdate ./anchors.tx -channelID ${TEST_CHANNEL} -asOrg ${ORG}MSP
