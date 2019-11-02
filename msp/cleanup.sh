#!/bin/bash
# cleanup k8s PVs after MSP bootstrap
# usage: cleanup.sh <org_name> <env>
# where config parameters for the org are specified in ../config/org_name.env, e.g.
#   cleanup.sh netop1
# use config parameters specified in ../config/netop1.env
# second parameter env can be k8s or aws to use local host or efs persistence, default k8s for local persistence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
ENV_TYPE=${2:-"k8s"}
source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${1:-"netop1"} ${ENV_TYPE}

echo "cleanup K8s PVs"
kubectl delete -f ${DATA_ROOT}/tool/k8s/tool.yaml
kubectl delete -f ${DATA_ROOT}/tool/k8s/tool-pv.yaml
kubectl delete -f ${DATA_ROOT}/tool/k8s/namespace.yaml
