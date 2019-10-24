#!/bin/bash
# setup variables for target environment, i.e., docker, k8s, aws, etc
# usage: setup.sh <org_name> <env>
# it uses config parameters of the specified org as defined in ../config/org.env, e.g.
#   setup.sh netop1 docker
# using config parameters specified in ../config/netop1.env

curr_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source $(dirname "${curr_dir}")/config/${1:-"netop1"}.env
ORG=${FABRIC_ORG%%.*}

if [ "${2}" == "k8s" ]; then
  # config for docker-desktop on Mac
  DNS_IP=$(kubectl get svc --all-namespaces -o wide | grep kube-dns | awk '{print $4}')
  SVC_DOMAIN=${ORG}.svc.cluster.local
  echo "setup for Kubernetes with service domain ${SVC_DOMAIN}"
fi