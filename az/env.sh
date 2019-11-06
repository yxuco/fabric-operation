#!/bin/bash
# set Azure environment for a specified $ENV_NAME and $AZ_REGION
# usage: source env.sh env region
# default value: ENV_NAME="fab", AZ_REGION="westus2"

# number of instances to create for the cluster
export AKS_NODE_COUNT=3
# type of node instances to create
export AKS_NODE_SIZE=Standard_DS2_v2
export AKS_DISK_SIZE=30
# type of persistent data store
export STORAGE_TYPE=Standard_LRS

##### usually you do not need to modify parameters below this line

# return the full path of this script
function getScriptDir {
  local src="${BASH_SOURCE[0]}"
  while [ -h "$src" ]; do
    local dir ="$( cd -P "$( dirname "$src" )" && pwd )"
    src="$( readlink "$src" )"
    [[ $src != /* ]] && src="$dir/$src"
  done
  cd -P "$( dirname "$src" )" 
  pwd
}

if [[ ! -z "${1}" ]]; then
  export ENV_NAME=${1}
fi
if [[ -z "${ENV_NAME}" ]]; then
  export ENV_NAME="fab"
fi
if [[ ! -z "${2}" ]]; then
  export AZ_REGION=${2}
fi
if [[ -z "${AKS_REGION}" ]]; then
  export AZ_REGION="westus2"
fi

export RESOURCE_GROUP=${ENV_NAME}RG
export STORAGE_ACCT=${ENV_NAME}store
# storage account secret key will be updated when storage is created
export STORAGE_KEY=+WQuW4gKHk/+d3birZ9/E9PcJ/xPIgu2ABXbfMo3el7znKV9pi3/3hVY4lekFTlqd3G0OSp6OQGlfXaOGwAhpQ==
export STORAGE_SHARE=${ENV_NAME}share
export SMB_PATH=//${STORAGE_ACCT}.file.core.windows.net/${STORAGE_SHARE}
export AKS_CLUSTER=${ENV_NAME}AKSCluster
export BASTION_HOST=${ENV_NAME}Bastion
# public IP will be updated when bastion host is created
export BASTION_IP=51.141.165.30
export BASTION_USER=${ENV_NAME}

export SCRIPT_HOME=$(getScriptDir)
export KUBECONFIG=${SCRIPT_HOME}/config/config-${ENV_NAME}.yaml
if [ ! -d "${SCRIPT_HOME}/config" ]; then
  mkdir -p ${SCRIPT_HOME}/config
fi
