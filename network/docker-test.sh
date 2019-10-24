#!/bin/bash
# execute smoke test for docker-compose on fabric network for a specified org
# usage: docker-test.sh <org_name>
# where config parameters for the org are specified in ../config/org.env, e.g.
#   docker-test.sh netop1
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source $(dirname "${SCRIPT_DIR}")/config/${1:-"netop1"}.env
MSP_DIR=$(dirname "${SCRIPT_DIR}")/${FABRIC_ORG}

cp ${SCRIPT_DIR}/docker-test-sample.sh ${MSP_DIR}/network
docker exec -it cli bash -c './config/network/docker-test-sample.sh'
