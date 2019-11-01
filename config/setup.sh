#!/bin/bash
# setup variables for target environment, i.e., docker, k8s, aws, etc
# usage: setup.sh <org_name> <env>
# it uses config parameters of the specified org as defined in org_name.env, e.g.
#   setup.sh netop1 docker
# using config parameters specified in ./netop1.env

curr_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source ${curr_dir}/${1:-"netop1"}.env
ORG=${FABRIC_ORG%%.*}

# AWS EFS variables populated by aws startup
AWS_MOUNT_POINT=opt/share
AWS_FSID=fs-0a0219a1

target=${2:-"docker"}
if [ "${target}" == "docker" ]; then
  echo "use docker-compose"
  SVC_DOMAIN=""
else
  # config for kubernetes
  echo "use kubernetes"
  DNS_IP=$(kubectl get svc --all-namespaces -o wide | grep kube-dns | awk '{print $4}')
  SVC_DOMAIN="${ORG}.svc.cluster.local"
  echo "setup Kubernetes with service domain ${SVC_DOMAIN}, and DNS ${DNS_IP}"
fi

if [ "${target}" == "aws" ]; then
  DATA_ROOT="/${AWS_MOUNT_POINT}/${FABRIC_ORG}"
  # Kubernetes persistence type: local | efs
  K8S_PERSISTENCE="efs"
else
  DATA_ROOT=$(dirname "${curr_dir}")/${FABRIC_ORG}
  K8S_PERSISTENCE="local"
fi
echo "set persistent data root ${DATA_ROOT}"
mkdir -p ${DATA_ROOT}
