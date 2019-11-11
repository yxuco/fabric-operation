#!/bin/bash
# create all AKS cluster and Azure File storage
# usage: az-util.sh <cmd> [-n <name>] [-r <region>]
# e.g., az-util.sh create -n fab -r westus2

cd "$( dirname "${BASH_SOURCE[0]}" )"

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  az-util.sh <cmd> [-n <name>] [-r <region>]"
  echo "    <cmd> - one of 'create', or 'cleanup'"
  echo "      - 'create' - create AKS cluster and Azure Files storage"
  echo "      - 'cleanup' - shutdown AKS cluster and cleanup Azure Files storage"
  echo "    -n <name> - prefix name of EKS cluster, e.g., fab (default)"
  echo "    -r <region> - Azure location to host the cluster, e.g. 'westus2' (default)"
  echo "  az-util.sh -h (print this message)"
}

CMD=${1}
shift
while getopts "h?n:r:" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  n)
    ENV_NAME=$OPTARG
    ;;
  r)
    AZ_REGION=$OPTARG
    ;;
  esac
done

if [ -z "${ENV_NAME}" ]; then
  ENV_NAME="fab"
fi

if [ -z "${AZ_REGION}" ]; then
    AZ_REGION="westus2"
fi

case "${CMD}" in
create)
  echo "create AKS cluster - ENV_NAME: ${ENV_NAME}, AZ_REGION: ${AZ_REGION}"
  ./create-cluster.sh ${ENV_NAME} ${AZ_REGION}
  ./create-storage.sh ${ENV_NAME} ${AZ_REGION}
  ./create-bastion.sh ${ENV_NAME} ${AZ_REGION}
  ;;
cleanup)
  echo "cleanup AKS cluster - ENV_NAME: ${ENV_NAME}, AZ_REGION: ${AZ_REGION}"
  source env.sh ${ENV_NAME} ${AZ_REGION}

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
  ;;
*)
  printHelp
  exit 1
esac
