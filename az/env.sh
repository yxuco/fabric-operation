#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# set Azure environment for a specified $ENV_NAME and $AZ_REGION
# usage: source env.sh env region
# default value: ENV_NAME="fab", AZ_REGION="westus2"

# number of instances to create for the cluster
export AKS_NODE_COUNT=3
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

export ENV_NAME=${1}
export AZ_REGION=${2}

export RESOURCE_GROUP=${ENV_NAME}RG
export STORAGE_ACCT=${ENV_NAME}store
export STORAGE_SHARE=${ENV_NAME}share
export SMB_PATH=//${STORAGE_ACCT}.file.core.windows.net/${STORAGE_SHARE}
export AKS_CLUSTER=${ENV_NAME}AKSCluster
export BASTION_HOST=${ENV_NAME}Bastion
# public IP will be updated when bastion host is created
export BASTION_IP=52.151.28.244
export BASTION_USER=${ENV_NAME}

export SCRIPT_HOME=$(getScriptDir)
export KUBECONFIG=${SCRIPT_HOME}/config/config-${ENV_NAME}.yaml
if [ ! -d "${SCRIPT_HOME}/config" ]; then
  mkdir -p ${SCRIPT_HOME}/config
fi
