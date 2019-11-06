#!/bin/bash
# stop fabric-ca server and client for a specified org,
#   with optional target env, i.e., docker, k8s, aws, etc, to provide extra SVC_DOMAIN config
# usage: stop-ca.sh <org_name> <env>
# where config parameters for the org are specified in ../config/org_name.env, e.g.
#   stop-ca.sh netop1
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
ENV_TYPE=${2:-"k8s"}
source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${1:-"netop1"} ${ENV_TYPE}
ORG_DIR=${DATA_ROOT}/canet

if [ "${ENV_TYPE}" == "docker" ]; then
  echo "stop docker containers"
  docker-compose -f ${ORG_DIR}/docker/docker-compose.yaml down --volumes --remove-orphans
else
  echo "stop k8s CA PODs"
  kubectl delete -f ${ORG_DIR}/k8s/ca.yaml
  kubectl delete -f ${ORG_DIR}/k8s/ca-pv.yaml
fi

echo "cleanup ca-client"
${surm} -R ${ORG_DIR}/ca-client/*
