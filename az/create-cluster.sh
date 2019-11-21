#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create Azure AKS cluster for a specified $ENV_NAME and $AZ_REGION
# usage: create-cluster.sh env region
# default value: ENV_NAME="fab", AZ_REGION="westus2"

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

echo "create AKS cluster ${AKS_CLUSTER} at location ${AZ_REGION}"
echo "it may take 9-10 minutes ..."
starttime=$(date +%s)

# create resource group if it does not exist already
check=$(az group show -g ${RESOURCE_GROUP} --query "properties.provisioningState" -o tsv)
if [ "${check}" == "Succeeded" ]; then
  echo "resource group ${RESOURCE_GROUP} is already provisioned"
else
  echo "create resource group ${RESOURCE_GROUP} at ${AZ_REGION} ..."
  az group create -l ${AZ_REGION} -n ${RESOURCE_GROUP}
fi

# create AKS cluster if it does not exist already
check=$(az aks show -g ${RESOURCE_GROUP} -n ${AKS_CLUSTER} --query "provisioningState" -o tsv)
if [ "${check}" == "Succeeded" ]; then
  echo "AKS cluster ${AKS_CLUSTER} is already provisioned"
else
  echo "create AKS cluster ${AKS_CLUSTER} ..."
  az aks create -g ${RESOURCE_GROUP} -n ${AKS_CLUSTER} -c ${AKS_NODE_COUNT} -u ${ENV_NAME} \
    --generate-ssh-keys --enable-addons monitoring --nodepool-name ${ENV_NAME}
  echo "collect cluster config file ${SCRIPT_HOME}/config/config-${ENV_NAME}.yaml ..."
  az aks get-credentials -g ${RESOURCE_GROUP} -n ${AKS_CLUSTER} -f ${SCRIPT_HOME}/config/config-${ENV_NAME}.yaml --overwrite-existing
fi
echo "AKS cluster ${AKS_CLUSTER} created in $(($(date +%s)-starttime)) seconds."

hash kubectl
if [ "$?" -eq 0 ]; then
  echo "verify nodes in AKS cluster ${AKS_CLUSTER}"
  kubectl get nodes
fi
