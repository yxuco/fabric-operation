#!/bin/bash
# cleanup Azure nodes and storage data for a specified $ENV_NAME and $AZ_REGION
# usage: cleanup-all.sh env region
# default value: ENV_NAME="fab", AZ_REGION="westus2"

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

starttime=$(date +%s)
echo "cleanup may take 10-11 mminutes ..."

echo "delete bastion host ${BASTION_HOST}"
az vm delete -n ${BASTION_HOST} -g ${RESOURCE_GROUP} -y
echo "delete Azure File storage ${STORAGE_ACCT}"
az storage account delete -n ${STORAGE_ACCT} -y

echo "delete AKS cluster ${AKS_CLUSTER}"
az aks delete -g ${RESOURCE_GROUP} -n ${AKS_CLUSTER} -y
echo "delete resource group ${RESOURCE_GROUP}"
az group delete -n ${RESOURCE_GROUP} -y

echo "Cleaned up ${RESOURCE_GROUP} in $(($(date +%s)-starttime)) seconds."
