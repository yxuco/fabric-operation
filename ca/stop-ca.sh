#!/bin/bash
# stop fabric-ca server and client for a specified org
# usage: stop-ca.sh <org_name>
# where config parameters for the org are specified in ../config/org.env, e.g.
#   stop-ca.sh netop1
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source $(dirname "${SCRIPT_DIR}")/config/${1:-"netop1"}.env
ORG_DIR=$(dirname "${SCRIPT_DIR}")/${FABRIC_ORG}/canet

docker-compose -f ${ORG_DIR}/docker-compose.yaml down --volumes --remove-orphans
rm -R ${ORG_DIR}/ca-client
