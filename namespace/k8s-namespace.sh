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

# set k8s default namespace
function setDefaultNamespace {
  local curr=$(kubectl config current-context)
  local c_namespace=$(kubectl config view -o=jsonpath="{.contexts[?(@.name=='${curr}')].context.namespace}")
  if [ "${c_namespace}" != "${ORG}" ]; then
    local c_user=$(kubectl config view -o=jsonpath="{.contexts[?(@.name=='${curr}')].context.user}")
    local c_cluster=$(kubectl config view -o=jsonpath="{.contexts[?(@.name=='${curr}')].context.cluster}")
    if [ ! -z "${c_cluster}" ]; then
      echo "set default kube namespace ${ORG} for cluster ${c_cluster} and user ${c_user}"
      kubectl config set-context ${ORG} --namespace=${ORG} --cluster=${c_cluster} --user=${c_user}
      kubectl config use-context ${ORG}
    else
      echo "failed to set default context for namespace ${ORG}"
    fi
  else
    echo "namespace ${ORG} is already set as default"
  fi
}

function main {
  ${sumd} -p ${DATA_ROOT}/namespace/k8s

  echo "create k8s namespace ${ORG}"
  printK8sNamespace | ${stee} ${DATA_ROOT}/namespace/k8s/namespace.yaml > /dev/null
  kubectl create -f ${DATA_ROOT}/namespace/k8s/namespace.yaml

  if [ "${ENV_TYPE}" == "az" ]; then
    # create secret for Azure File storage
    echo "create Azure storage secret"
    printAzureSecretYaml | ${stee} ${DATA_ROOT}/namespace/k8s/azure-secret.yaml > /dev/null
    kubectl create -f ${DATA_ROOT}/namespace/k8s/azure-secret.yaml
  fi

  setDefaultNamespace
}

main