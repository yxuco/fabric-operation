#!/bin/bash
# start network for a specified org
# usage: start-network.sh <org_name>
# where config parameters for the org are specified in ../config/org.env, e.g.
#   stop-network.sh netop1
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source $(dirname "${SCRIPT_DIR}")/config/${1:-"netop1"}.env
MSP_DIR=$(dirname "${SCRIPT_DIR}")/${FABRIC_ORG}

COMPOSE_FILES="-f ${MSP_DIR}/network/docker-compose.yaml"
if [ ! -z "${CA_PORT}" ]; then
  COMPOSE_FILES="${COMPOSE_FILES} -f ${MSP_DIR}/network/docker-compose-ca.yaml"
fi
docker-compose ${COMPOSE_FILES} up -d
