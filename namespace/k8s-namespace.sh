#!/bin/bash
# create k8s namespace for a specified org,
#   if the optional target env is az, create the storage account secret based on config file in $HOME/.azure/store-secret
# usage: k8s-namespace.sh <org_name> <env>
# where config parameters for the org are specified in ../config/org_name.env, e.g.
#   k8s-namespace.sh netop1 az
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"
ENV_TYPE=${2:-"k8s"}
source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${1:-"netop1"} ${ENV_TYPE}

if [ "${ENV_TYPE}" == "az" ]; then
  # read secret key for Azure storage account
  source ${HOME}/.azure/store-secret
fi

function printK8sNamespace {
  echo "
apiVersion: v1
kind: Namespace
metadata:
  name: ${ORG}
  labels:
    use: hyperledger"
}

# create azure-secret yaml
function printAzureSecretYaml {
  user=$(echo -n "${STORAGE_ACCT}" | base64 -w 0)
  key=$(echo -n "${STORAGE_KEY}" | base64 -w 0)
  echo "---
apiVersion: v1
kind: Secret
metadata:
  name: azure-secret
  namespace: ${ORG}
type: Opaque
data:
  azurestorageaccountname: ${user}
  azurestorageaccountkey: ${key}"
}

function main {
  ${sumd} -p ${DATA_ROOT}/namespace/k8s

  echo "create k8s namespace ${ORG}"
  printNamespaceYaml | ${stee} ${DATA_ROOT}/namespace/k8s/namespace.yaml > /dev/null
  kubectl create -f ${DATA_ROOT}/namespace/k8s/namespace.yaml

  if [ "${ENV_TYPE}" == "az" ]; then
    # create secret for Azure File storage
    echo "create Azure storage secret"
    printAzureSecretYaml | ${stee} ${DATA_ROOT}/namespace/k8s/azure-secret.yaml > /dev/null
    kubectl create -f ${DATA_ROOT}/namespace/k8s/azure-secret.yaml
  fi
}

# TODO: set default namespace
#kubectl config set-context ${ns} --namespace=${ns} --cluster=${AKS_CLUSTER} --user=clusterUser_${RESOURCE_GROUP}_${AKS_CLUSTER}
#kubectl config use-context ${ns}

main