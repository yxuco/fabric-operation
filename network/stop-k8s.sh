#!/bin/bash
# stop fabric network for Mac docker-desktop Kubernetes
# usage: stop-k8s.sh <org_name> <env> [true|false]
# it uses config parameters of the specified org as defined in ../config/org.env, e.g.
#   stop-k8s.sh netop1
# using config parameters specified in ../config/netop1.env
# second parameter env can be k8s or aws to use local host or efs persistence, default k8s for local persistence
# cleanup persistent data if the third parameter is true.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
ENV_TYPE=${2:-"k8s"}
source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${1:-"netop1"} ${ENV_TYPE}

# set list of orderers from config
function getOrderers {
  ORDERERS=()
  seq=${ORDERER_MIN:-"0"}
  max=${ORDERER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    ORDERERS+=("orderer-${seq}")
    seq=$((${seq}+1))
  done
}

# set list of peers from config
function getPeers {
  PEERS=()
  seq=${PEER_MIN:-"0"}
  max=${PEER_MAX:-"0"}
  until [ "${seq}" -ge "${max}" ]; do
    PEERS+=("peer-${seq}")
    seq=$((${seq}+1))
  done
}

echo "stop cli pod ..."
kubectl delete -f ${DATA_ROOT}/network/k8s/cli.yaml
kubectl delete -f ${DATA_ROOT}/network/k8s/cli-pv.yaml

echo "stop fabric network ..."
kubectl delete -f ${DATA_ROOT}/network/k8s/peer.yaml
kubectl delete -f ${DATA_ROOT}/network/k8s/peer-pv.yaml
kubectl delete -f ${DATA_ROOT}/network/k8s/orderer.yaml
kubectl delete -f ${DATA_ROOT}/network/k8s/orderer-pv.yaml

if [ "${3}" == "true" ]; then
  echo "clean up orderer ledger files ..."
  getOrderers
  for ord in "${ORDERERS[@]}"; do
    rm -R ${DATA_ROOT}/orderers/${ord}/data/*
  done

  echo "clean up peer ledger files ..."
  getPeers
  for p in "${PEERS[@]}"; do
    rm -R ${DATA_ROOT}/peers/${p}/data/*
  done
fi
