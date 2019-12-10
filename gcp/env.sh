#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# set GCP environment for a specified $ENV_NAME and $GCP_ZONE
# usage: source env.sh env zone
# e.g.: ENV_NAME="fab", GCP_ZONE="us-west1-c"

# GCP project name
export GCP_PROJECT=fab-project-002
# number of instances to create for the cluster
export GKE_NODE_COUNT=3

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
export GCP_ZONE=${2}

export GKE_CLUSTER=${ENV_NAME}-cluster
export FILESTORE=${ENV_NAME}store
export FILE_SHARE=${ENV_NAME}
export BASTION_HOST=${ENV_NAME}-bastion
export SSH_KEY=${ENV_NAME}-key
export BASTION_USER=${ENV_NAME}

export SCRIPT_HOME=$(getScriptDir)
export KUBECONFIG=${SCRIPT_HOME}/config/config-${ENV_NAME}
if [ ! -d "${SCRIPT_HOME}/config" ]; then
  mkdir -p ${SCRIPT_HOME}/config
fi
