#!/bin/bash
# setup variables for target environment, i.e., docker, k8s, aws, az, etc
# usage: setup.sh <org_name> <env>
# it uses config parameters of the specified org as defined in org_name.env, e.g.
#   setup.sh netop1 docker
# using config parameters specified in ./netop1.env

curr_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
source ${curr_dir}/${1:-"netop1"}.env
ORG=${FABRIC_ORG%%.*}

# AWS EFS variables populated by aws startup
AWS_MOUNT_POINT=mnt/share
AWS_FSID=fs-aec3d805

# Azure File variables populated by Azure startup
AZ_MOUNT_POINT=mnt/share
AZ_STORAGE_SHARE=fabshare

# Google Filestore variables populated by GKE startup
GKE_MOUNT_POINT=mnt/share
GKE_STORE_IP=10.216.129.154

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

sumd="sudo mkdir"
sucp="sudo cp"
surm="sudo rm"
sumv="sudo mv"
stee="sudo tee"
if [ "${target}" == "aws" ]; then
  DATA_ROOT="/${AWS_MOUNT_POINT}/${FABRIC_ORG}"
  # Kubernetes persistence type: local | efs | azf
  K8S_PERSISTENCE="efs"
elif [ "${target}" == "az" ]; then
  DATA_ROOT="/${AZ_MOUNT_POINT}/${FABRIC_ORG}"
  K8S_PERSISTENCE="azf"
else
  DATA_ROOT=$(dirname "${curr_dir}")/${FABRIC_ORG}
  K8S_PERSISTENCE="local"
  sumd="mkdir"
  sucp="cp"
  surm="rm"
  sumv="mv"
  stee="tee"
fi
echo "set persistent data root ${DATA_ROOT}"
${sumd} -p ${DATA_ROOT}
