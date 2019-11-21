#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create Azure Files storage for a specified $ENV_NAME and $AZ_REGION
# usage: create-storage.sh env region
# default value: ENV_NAME="fab", AZ_REGION="westus2"

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

echo "create Azure File share ${STORAGE_SHARE} at location ${AZ_REGION}"
starttime=$(date +%s)

# create storage account if it does not exist already
check=$(az storage account show -n ${STORAGE_ACCT} -g ${RESOURCE_GROUP} --query "statusOfPrimary" -o tsv)
if [ "${check}" == "available" ]; then
  echo "storage account ${STORAGE_ACCT} is already available"
else
  echo "create storage account ${STORAGE_ACCT} at ${AZ_REGION} ..."
  az storage account create -n ${STORAGE_ACCT} -g ${RESOURCE_GROUP} -l ${AZ_REGION} --sku ${STORAGE_TYPE} --kind StorageV2
fi
echo "collect account secret key for ${STORAGE_ACCT} ..."
skey=$(az storage account keys list -g ${RESOURCE_GROUP} -n ${STORAGE_ACCT} --query "[0].value" -o tsv)

# store env for bastion setup
echo "export STORAGE_ACCT=${STORAGE_ACCT}" > ./config/env.sh
echo "export STORAGE_SHARE=${STORAGE_SHARE}" >> ./config/env.sh
echo "export SMB_PATH=${SMB_PATH}" >> ./config/env.sh
echo "export STORAGE_KEY=${skey}" >> ./config/env.sh

# store Azure secret in $HOME/.azure/store-secret
mkdir -p ${HOME}/.azure
echo "STORAGE_ACCT=${STORAGE_ACCT}" > ${HOME}/.azure/store-secret
echo "STORAGE_KEY=${skey}" >> ${HOME}/.azure/store-secret

# create Azure file share if it does not exist already
conn=$(az storage account show-connection-string -n ${STORAGE_ACCT} -g ${RESOURCE_GROUP} -o tsv)
check=$(az storage share show -n ${STORAGE_SHARE} --connection-string ${conn} --query "name" -o tsv)
if [ "${check}" == "${STORAGE_SHARE}" ]; then
  echo "Azure File share ${STORAGE_SHARE} already exists"
else
  echo "create Azure File share ${STORAGE_SHARE} using connection ${conn} ..."
  az storage share create -n ${STORAGE_SHARE} --connection-string ${conn}
fi
echo "Azure File share ${STORAGE_SHARE} created in $(($(date +%s)-starttime)) seconds."
