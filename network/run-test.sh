#!/bin/bash
# execute smoke test on fabric network for a specified org
# usage: run-test.sh <org_name>
# where config parameters for the org are specified in ../config/org.env, e.g.
#   run-test.sh netop1
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source $(dirname "${SCRIPT_DIR}")/config/${1:-"netop1"}.env
MSP_DIR=$(dirname "${SCRIPT_DIR}")/${FABRIC_ORG}

cp ${SCRIPT_DIR}/test-sample.sh ${MSP_DIR}/network
docker exec -it cli bash -c './config/network/test-sample.sh'
