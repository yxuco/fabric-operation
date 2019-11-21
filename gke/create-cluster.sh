#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create Google cloud GKE cluster for a specified $ENV_NAME and $GCP_ZONE
# usage: create-cluster.sh env zone
# example value: ENV_NAME="fab", GCP_ZONE="us-west1-c"

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

echo "create GKE cluster ${GKE_CLUSTER} at zone ${GCP_ZONE}"
starttime=$(date +%s)

# setup GCP account and services
echo "verify GCP project ${GCP_PROJECT}"
check=$(gcloud projects describe ${GCP_PROJECT} --format="csv[no-heading](name)")
if [ "${check}" == "${GCP_PROJECT}" ]; then
  echo "configure account default project ${GCP_PROJECT} and zone ${GCP_ZONE}"
  gcloud config set project ${GCP_PROJECT}
  gcloud config set compute/zone ${GCP_ZONE}
  gcloud config set filestore/zone ${GCP_ZONE}
  gcloud services enable container.googleapis.com --project ${GCP_PROJECT}
  gcloud services enable file.googleapis.com --project ${GCP_PROJECT}
else
  echo "Error: project ${GCP_PROJECT} does not exist, edit 'env.sh' to select an existing project"
  exit 1
fi

# create GKE cluster
check=$(gcloud container clusters describe ${GKE_CLUSTER} --format="csv[no-heading](status,zone)")
if [ "${check}" == "RUNNING,${GCP_ZONE}" ]; then
  echo "GKE cluster ${GKE_CLUSTER} already running in zone ${GCP_ZONE}"
else
  export KUBECONFIG=${KUBECONFIG}
  gcloud container clusters create ${GKE_CLUSTER} --node-locations=${GCP_ZONE} --num-nodes=${GKE_NODE_COUNT}
fi

echo "GKE cluster ${GKE_CLUSTER} created in $(($(date +%s)-starttime)) seconds."

hash kubectl
if [ "$?" -eq 0 ]; then
  echo "verify nodes in GKE cluster ${GKE_CLUSTER}"
  kubectl get nodes
fi
