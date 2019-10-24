#!/bin/bash
# stop fabric network for Mac docker-desktop Kubernetes
# usage: stop-k8s.sh <org_name>
# it uses config parameters of the specified org as defined in ../config/org.env, e.g.
#   stop-k8s.sh netop1
# using config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source ${SCRIPT_DIR}/setup.sh ${1:-"netop1"} k8s
MSP_DIR=$(dirname "${SCRIPT_DIR}")/${FABRIC_ORG}

echo "stop cli pod ..."
kubectl delete -f ${MSP_DIR}/network/k8s-cli.yaml

echo "stop fabric network ..."
kubectl delete -f ${MSP_DIR}/network/k8s-peer.yaml
kubectl delete -f ${MSP_DIR}/network/k8s-peer-pv.yaml
kubectl delete -f ${MSP_DIR}/network/k8s-orderer.yaml
kubectl delete -f ${MSP_DIR}/network/k8s-orderer-pv.yaml
kubectl delete -f ${MSP_DIR}/network/k8s-namespace.yaml

echo "clean up orderer ledger files ..."
rm -R ${MSP_DIR}/k8s/data/orderer-0/*