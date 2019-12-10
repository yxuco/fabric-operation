#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create k8s namespace for a specified org,
#   if the optional target env is az, create the storage account secret based on config file in $HOME/.azure/store-secret
# usage: k8s-namespace.sh <cmd> [-p <property file>] [-t <env type>]
# where property file is specified in ../config/org_name.env, e.g.
#   k8s-namespace.sh create -p netop1 -t az
# use config parameters specified in ../config/netop1.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; echo "$(pwd)")"

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

function createNamespace {
  ${sumd} -p ${DATA_ROOT}/namespace/k8s

  echo "check if namespace ${ORG} exists"
  kubectl get namespace ${ORG}
  if [ "$?" -ne 0 ]; then
    echo "create k8s namespace ${ORG}"
    printK8sNamespace | ${stee} ${DATA_ROOT}/namespace/k8s/namespace.yaml > /dev/null
    kubectl create -f ${DATA_ROOT}/namespace/k8s/namespace.yaml
  fi

  if [ "${ENV_TYPE}" == "az" ]; then
    # create secret for Azure File storage
    echo "create Azure storage secret"
    printAzureSecretYaml | ${stee} ${DATA_ROOT}/namespace/k8s/azure-secret.yaml > /dev/null
    kubectl create -f ${DATA_ROOT}/namespace/k8s/azure-secret.yaml
  fi

  setDefaultNamespace
}

function deleteNamespace {
  kubectl delete -f ${DATA_ROOT}/namespace/k8s/namespace.yaml
  if [ "${ENV_TYPE}" == "az" ]; then
    kubectl delete -f ${DATA_ROOT}/namespace/k8s/azure-secret.yaml
  fi
}

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  k8s-namespace.sh <cmd> [-p <property file>] [-t <env type>]"
  echo "    <cmd> - one of 'create', or 'delete'"
  echo "      - 'create' - create k8s namespace for the organization defined in network spec; for Azure, also create storage secret"
  echo "      - 'delete' - delete k8s namespace, for Azure, also delete the storage secret"
  echo "    -p <property file> - the .env file in config folder that defines network properties, e.g., netop1 (default)"
  echo "    -t <env type> - deployment environment type: one of 'k8s' (default), 'aws', 'az', or 'gcp'"
  echo "  k8s-namespace.sh -h (print this message)"
}

ORG_ENV="netop1"

CMD=${1}
shift
while getopts "h?p:t:" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  p)
    ORG_ENV=$OPTARG
    ;;
  t)
    ENV_TYPE=$OPTARG
    ;;
  esac
done

source $(dirname "${SCRIPT_DIR}")/config/setup.sh ${ORG_ENV} ${ENV_TYPE}
if [ "${ENV_TYPE}" == "az" ]; then
  # read secret key for Azure storage account
  source ${HOME}/.azure/store-secret
  if [ -z "${STORAGE_ACCT}" ] || [ -z "${STORAGE_KEY}" ]; then
    echo "Error: 'STORAGE_ACCT' and 'STORAGE_KEY' must be set in ${HOME}/.azure/store-secret for Azure"
    exit 1
  fi
elif [ "${ENV_TYPE}" == "docker" ]; then
  echo "No need to create namespace for docker"
  exit 0
fi

case "${CMD}" in
create)
  echo "create namespace ${ORG} for: ${ORG_ENV} ${ENV_TYPE}"
  createNamespace
  ;;
delete)
  echo "delete namespace ${ORG}: ${ORG_ENV} ${ENV_TYPE}"
  deleteNamespace
  ;;
*)
  printHelp
  exit 1
esac
