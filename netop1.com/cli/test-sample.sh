#!/bin/bash
# Run this script in cli docker container to create test channel and test a sample chaincode
# usage: test-sample.sh

echo "create channel ${TEST_CHANNEL} ..."
peer channel create -o ${ORDERER_URL} -c ${TEST_CHANNEL} -f channel.tx --tls --cafile $ORDERER_CA

echo "Join channel ${TEST_CHANNEL} ..."
peer channel join -b mychannel.block
peer channel update -o ${ORDERER_URL} -c ${TEST_CHANNEL} -f anchors.tx --tls --cafile $ORDERER_CA

CC_SRC_PATH="github.com/chaincode/chaincode_example02/go/"
echo "Install chaincode from ${CC_SRC_PATH} ..."
peer chaincode install -n mycc -v 1.0 -l golang -p ${CC_SRC_PATH}
peer chaincode instantiate -o ${ORDERER_URL} --tls --cafile ${ORDERER_CA} -C ${TEST_CHANNEL} -n mycc -l golang -v 1.0 -c '{"Args":["init","a","100","b","200"]}' -P "OR ('${ORG}MSP.peer')"

echo "Wait 10s before testing chaincode ..."
sleep 10
peer chaincode query -C ${TEST_CHANNEL} -n mycc -c '{"Args":["query","a"]}'
peer chaincode invoke -o ${ORDERER_URL} --tls --cafile $ORDERER_CA -C ${TEST_CHANNEL} -n mycc -c '{"Args":["invoke","a","b","10"]}'
echo "wait 5s for transaction to commit ..."
sleep 5
echo "Following query should return 90"
peer chaincode query -C ${TEST_CHANNEL} -n mycc -c '{"Args":["query","a"]}'
